import XCTest
@testable import iris

final class VisionRouterTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        ConfigManager.shared.auxiliaryVisionEngine = ""
        ConfigManager.shared.auxiliaryVisionModel = ""
    }

    func testPrimaryModelVisionCapabilityDetection() {
        XCTAssertTrue(VisionRouter.isVisionCapable(modelName: "gemini-2.0-flash"))
        XCTAssertTrue(VisionRouter.isVisionCapable(modelName: "claude-3-5-sonnet"))
        XCTAssertTrue(VisionRouter.isVisionCapable(modelName: "gpt-4o"))
        XCTAssertTrue(VisionRouter.isVisionCapable(modelName: "llava-v1.6"))
        XCTAssertFalse(VisionRouter.isVisionCapable(modelName: "deepseek-r1"))
        XCTAssertFalse(VisionRouter.isVisionCapable(modelName: "qwen2.5-coder"))
    }
    
    func testProcessTextOnlyImagesNoImages() async {
        let nonImageAttachment = FileAttachment(
            filename: "notes.txt",
            fileURL: URL(fileURLWithPath: "/tmp/notes.txt"),
            mimeType: "text/plain",
            fileSize: 100,
            category: .text
        )
        
        let result = await VisionRouter.processTextOnlyImages(attachments: [nonImageAttachment])
        XCTAssertEqual(result.descriptionText, "")
        XCTAssertTrue(result.warnings.isEmpty)
    }
    
    func testProcessTextOnlyImagesNoAuxiliaryConfigured() async {
        let imageAttachment = FileAttachment(
            filename: "screenshot.png",
            fileURL: URL(fileURLWithPath: "/tmp/screenshot.png"),
            mimeType: "image/png",
            fileSize: 500,
            category: .image
        )
        
        let result = await VisionRouter.processTextOnlyImages(attachments: [imageAttachment])
        XCTAssertEqual(result.descriptionText, "")
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.warnings[0].contains("does not support vision and no auxiliary vision model is configured"))
    }
    
    func testProcessTextOnlyImagesWithAuxiliaryModel() async throws {
        // Create temp image file
        let tempDir = FileManager.default.temporaryDirectory
        let imageURL = tempDir.appendingPathComponent("test_image_\(UUID().uuidString).png")
        let dummyData = "fake image data".data(using: .utf8)!
        try dummyData.write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }
        
        let imageAttachment = FileAttachment(
            filename: "test_image.png",
            fileURL: imageURL,
            mimeType: "image/png",
            fileSize: Int64(dummyData.count),
            category: .image
        )
        
        // Mock auxiliary engine
        final class MockVisionEngine: AuxiliaryInferenceEngine, @unchecked Sendable {
            var receivedImages: [String]?
            func loadModel(config: AuxiliaryModelConfig) async throws {}
            func unloadModel() async {}
            func generate(prompt: String, jsonSchema: String?) async throws -> String {
                return "A sample diagram showing workflow."
            }
            func generate(prompt: String, jsonSchema: String?, images: [String]?) async throws -> String {
                self.receivedImages = images
                return "A sample diagram showing workflow."
            }
        }
        
        let mockEngine = MockVisionEngine()
        AuxiliaryModelManager.shared.setMockEngine(mockEngine, for: "vision")
        ConfigManager.shared.auxiliaryVisionEngine = "ollama"
        ConfigManager.shared.auxiliaryVisionModel = "llava"
        
        let result = await VisionRouter.processTextOnlyImages(attachments: [imageAttachment])
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertTrue(result.descriptionText.contains("<image_description file=\"test_image.png\">"))
        XCTAssertTrue(result.descriptionText.contains("A sample diagram showing workflow."))
        XCTAssertTrue(result.descriptionText.contains("</image_description>"))
        XCTAssertEqual(mockEngine.receivedImages, [dummyData.base64EncodedString()])
    }
}
