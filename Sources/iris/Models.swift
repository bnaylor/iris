import Foundation

struct GeminiRequest: Codable {
    var contents: [Content]
    var systemInstruction: Content?
    var tools: [Tool]?
}

struct Content: Codable {
    var role: String?
    var parts: [Part]
}

struct Part: Codable {
    var text: String?
    var functionCall: FunctionCall?
    var functionResponse: FunctionResponse?
    var thought_signature: String?
    var thoughtSignature: String?
}

struct FunctionCall: Codable {
    var name: String
    var args: [String: String]
    var thought_signature: String?
    var thoughtSignature: String?
}

struct FunctionResponse: Codable {
    var name: String
    var response: [String: String]
}

struct Tool: Codable {
    var functionDeclarations: [FunctionDeclaration]
}

struct FunctionDeclaration: Codable {
    var name: String
    var description: String
    var parameters: Schema?
}

struct Schema: Codable {
    var type: String
    var properties: [String: Schema]?
    var required: [String]?
    var description: String?
}

struct GeminiResponse: Codable {
    var candidates: [Candidate]?
    var usageMetadata: UsageMetadata?
}

struct Candidate: Codable {
    var content: Content?
}

struct UsageMetadata: Codable, Sendable {
    var promptTokenCount: Int?
    var candidatesTokenCount: Int?
    var totalTokenCount: Int?
}
