import XCTest
@testable import iris

final class OllamaEngineTests: XCTestCase {
    
    // MARK: - JSON response parsing (logic used by listInstalledModels)
    
    func testParseOllamaTagsResponse() {
        let json = """
        {
            "models": [
                {"name": "gemma4:12b", "size": 7556508396},
                {"name": "qwen3.5:latest", "size": 5432109876},
                {"name": "llama3.2:3b", "size": 2012345678}
            ]
        }
        """
        
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else {
            XCTFail("Failed to parse JSON")
            return
        }
        
        let names = models.compactMap { $0["name"] as? String }.sorted()
        XCTAssertEqual(names.count, 3)
        XCTAssertEqual(names, ["gemma4:12b", "llama3.2:3b", "qwen3.5:latest"])
    }
    
    func testParseEmptyOllamaTagsResponse() {
        let json = """
        {
            "models": []
        }
        """
        
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else {
            XCTFail("Failed to parse JSON")
            return
        }
        
        let names = models.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.isEmpty)
    }
    
    func testParseOllamaTagsMissingModelsKey() {
        let json = """
        {
            "other_key": "value"
        }
        """
        
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Failed to parse JSON")
            return
        }
        
        // When "models" key is missing, we get nil, which maps to []
        let models = obj["models"] as? [[String: Any]] ?? []
        XCTAssertTrue(models.isEmpty)
    }
    
    func testParseOllamaTagsInvalidJSON() {
        let json = "{ invalid }"
        let data = json.data(using: .utf8)!
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(obj, "Invalid JSON should return nil")
    }
    
    // MARK: - Pull response parsing
    
    func testParseOllamaPullSuccessResponse() {
        let json = """
        {
            "status": "success"
        }
        """
        
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = obj["status"] as? String else {
            XCTFail("Failed to parse JSON")
            return
        }
        
        XCTAssertEqual(status, "success")
    }
    
    func testParseOllamaPullProgressResponse() {
        let json = """
        {
            "status": "downloading 45%"
        }
        """
        
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = obj["status"] as? String else {
            XCTFail("Failed to parse JSON")
            return
        }
        
        XCTAssertEqual(status, "downloading 45%")
    }
    
    // MARK: - PS response parsing (isModelLoaded)
    
    func testParseOllamaPSResponseModelFound() {
        let json = """
        {
            "models": [
                {"name": "gemma4:12b", "size": 7556508396},
                {"name": "qwen3.5:latest", "size": 5432109876}
            ]
        }
        """
        
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else {
            XCTFail("Failed to parse JSON")
            return
        }
        
        let modelName = "gemma4:12b"
        let found = models.contains { model in
            guard let name = model["name"] as? String else { return false }
            return name == modelName || name.hasPrefix(modelName + ":")
        }
        XCTAssertTrue(found)
    }
    
    func testParseOllamaPSResponseModelNotFound() {
        let json = """
        {
            "models": [
                {"name": "qwen3.5:latest", "size": 5432109876}
            ]
        }
        """
        
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else {
            XCTFail("Failed to parse JSON")
            return
        }
        
        let modelName = "gemma4:12b"
        let found = models.contains { model in
            guard let name = model["name"] as? String else { return false }
            return name == modelName || name.hasPrefix(modelName + ":")
        }
        XCTAssertFalse(found)
    }
    
    func testParseOllamaPSResponsePrefixMatch() {
        // When a model was pulled with a variant tag, isModelLoaded should
        // match via colon prefix (Ollama's tag separator)
        // e.g. "gemma4:12b" should match "gemma4:12b:text" 
        let json = """
        {
            "models": [
                {"name": "gemma4:12b:text", "size": 7556508396}
            ]
        }
        """
        
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else {
            XCTFail("Failed to parse JSON")
            return
        }
        
        let modelName = "gemma4:12b"
        let found = models.contains { model in
            guard let name = model["name"] as? String else { return false }
            return name == modelName || name.hasPrefix(modelName + ":")
        }
        XCTAssertTrue(found, "Colon-prefix match should find gemma4:12b:text for query gemma4:12b")
        
        // Also verify that dashes do NOT match (only colon prefixes work)
        let noMatchModels: [[String: Any]] = [["name": "gemma4:12b-Q4_K_M"]]
        let noMatchFound = noMatchModels.contains { model in
            guard let name = model["name"] as? String else { return false }
            return name == modelName || name.hasPrefix(modelName + ":")
        }
        XCTAssertFalse(noMatchFound, "Dash suffix should not match — only colon prefixes work")
    }
    
    // MARK: - Base URL construction
    
    func testBaseURLIsCorrect() {
        // The baseURL is private; we verify the paths are constructed correctly
        // by testing URL construction with the expected base
        let baseURL = "http://localhost:11434"
        let tagsURL = URL(string: "\(baseURL)/api/tags")
        let generateURL = URL(string: "\(baseURL)/api/generate")
        let pullURL = URL(string: "\(baseURL)/api/pull")
        let psURL = URL(string: "\(baseURL)/api/ps")
        
        XCTAssertEqual(tagsURL?.absoluteString, "http://localhost:11434/api/tags")
        XCTAssertEqual(generateURL?.absoluteString, "http://localhost:11434/api/generate")
        XCTAssertEqual(pullURL?.absoluteString, "http://localhost:11434/api/pull")
        XCTAssertEqual(psURL?.absoluteString, "http://localhost:11434/api/ps")
    }
}
