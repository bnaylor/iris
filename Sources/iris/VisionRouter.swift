import Foundation

public enum VisionRouter {
    public static func isVisionCapable(modelName: String) -> Bool {
        let name = modelName.lowercased()
        return name.contains("gemini") ||
               name.contains("gpt-4") ||
               name.contains("claude") ||
               name.contains("o1") ||
               name.contains("o3") ||
               name.contains("vision") ||
               name.contains("llava") ||
               name.contains("vl") ||
               name.contains("pixtral") ||
               name.contains("paligemma") ||
               name.contains("minicpm")
    }

    public static func processTextOnlyImages(attachments: [FileAttachment]) async -> (descriptionText: String, warnings: [String]) {
        let images = attachments.filter { $0.category == .image }
        guard !images.isEmpty else { return ("", []) }

        let config = ConfigManager.shared
        let auxEngineType = config.auxiliaryVisionEngine
        let auxModelName = config.auxiliaryVisionModel

        if auxEngineType.isEmpty || auxModelName.isEmpty {
            let primaryModel = config.getModel(for: .medium)
            return ("", ["Active model '\(primaryModel)' does not support vision and no auxiliary vision model is configured in Settings."])
        }

        guard let engineType = AuxiliaryEngineType(rawValue: auxEngineType) else {
            let primaryModel = config.getModel(for: .medium)
            return ("", ["Active model '\(primaryModel)' does not support vision and no auxiliary vision model is configured in Settings."])
        }

        var descriptions: [String] = []
        var warnings: [String] = []

        let auxConfig = AuxiliaryModelConfig(role: "vision", engineType: engineType, modelPathOrName: auxModelName)

        for img in images {
            do {
                let imgData = try Data(contentsOf: img.fileURL)
                let base64 = imgData.base64EncodedString()
                let prompt = "Describe this image in detail, including text, structure, and visual content, for an AI coding assistant."
                
                let auxiliaryEngine = try await AuxiliaryModelManager.shared.getEngine(for: "vision", config: auxConfig)
                let description = try await auxiliaryEngine.generate(prompt: prompt, jsonSchema: nil, images: [base64])
                
                descriptions.append("<image_description file=\"\(img.filename)\">\n\(description)\n</image_description>")
            } catch {
                warnings.append("Auxiliary vision model failed for \(img.filename): \(error.localizedDescription)")
            }
        }

        return (descriptions.joined(separator: "\n\n"), warnings)
    }
}
