import XCTest
@testable import iris

final class FileAttachmentSerializationTests: XCTestCase {
    func testFileAttachmentJSONEncodingAndDecoding() throws {
        let url = URL(fileURLWithPath: "/tmp/sample.png")
        let attachment = FileAttachment(
            id: UUID(),
            filename: "sample.png",
            fileURL: url,
            mimeType: "image/png",
            fileSize: 1024,
            category: .image
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(attachment)
        let decoded = try decoder.decode(FileAttachment.self, from: data)
        
        XCTAssertEqual(decoded.filename, "sample.png")
        XCTAssertEqual(decoded.mimeType, "image/png")
        XCTAssertEqual(decoded.fileSize, 1024)
        XCTAssertEqual(decoded.category, .image)
    }

    func testChatMessageBackwardsCompatibility() throws {
        let jsonWithoutAttachments = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "role": "user",
            "content": "Hello"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let msg = try decoder.decode(ChatMessage.self, from: jsonWithoutAttachments)
        XCTAssertEqual(msg.content, "Hello")
        XCTAssertTrue(msg.attachments.isEmpty)
    }
}
