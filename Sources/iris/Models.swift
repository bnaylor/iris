import Foundation

enum ModelTier: String, Codable {
    case easy
    case medium
    case hard
}

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

struct FunctionCall: Codable, Sendable {
    var name: String
    var args: [String: JSONValue]
    var id: String?
    var thought_signature: String?
    var thoughtSignature: String?
}

struct FunctionResponse: Codable, Sendable {
    var name: String
    var response: [String: JSONValue]
    var id: String?
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

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(String.self) { self = .string(x); return }
        if let x = try? container.decode(Int.self) { self = .int(x); return }
        if let x = try? container.decode(Double.self) { self = .double(x); return }
        if let x = try? container.decode(Bool.self) { self = .bool(x); return }
        if let x = try? container.decode([String: JSONValue].self) { self = .object(x); return }
        if let x = try? container.decode([JSONValue].self) { self = .array(x); return }
        if container.decodeNil() { self = .null; return }
        throw DecodingError.typeMismatch(JSONValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for JSONValue"))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let x): try container.encode(x)
        case .int(let x): try container.encode(x)
        case .double(let x): try container.encode(x)
        case .bool(let x): try container.encode(x)
        case .object(let x): try container.encode(x)
        case .array(let x): try container.encode(x)
        case .null: try container.encodeNil()
        }
    }
    
    public var stringValue: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .object: return "{...}"
        case .array: return "[...]"
        case .null: return "null"
        }
    }
    
    public var anyValue: Any {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .object(let dict): return dict.mapValues { $0.anyValue }
        case .array(let arr): return arr.map { $0.anyValue }
        case .null: return NSNull()
        }
    }
}
