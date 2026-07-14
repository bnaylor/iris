import XCTest
import GRDB
@testable import iris

final class HolographicMemoryTests: XCTestCase {
    
    var memoryManager: HolographicMemoryManager!
    
    override func setUpWithError() throws {
        // Initialize an in-memory database for fresh tests every time
        memoryManager = try HolographicMemoryManager(inMemory: true)
    }

    override func tearDownWithError() throws {
        memoryManager = nil
    }

    func testHolographicVectorEncoding() throws {
        // Test deterministic encoding
        let text = "Apple Silicon is incredibly fast"
        let vector1 = HolographicVector.encode(string: text)
        let vector2 = HolographicVector.encode(string: text)
        
        // Exact same string should produce exact same vector
        XCTAssertEqual(vector1.values, vector2.values, "Vectors for identical strings should be deterministic.")
        
        // Different string should produce different vector
        let vector3 = HolographicVector.encode(string: "Apple Silicon is incredibly slow")
        XCTAssertNotEqual(vector1.values, vector3.values, "Different strings should produce different vectors.")
        
        // Test similarity
        let sim = vector1.similarity(to: vector2)
        XCTAssertEqual(sim, 1.0, accuracy: 0.0001, "Identical vectors should have similarity near 1.0")
    }

    func testFactStorageAndRetrieval() throws {
        // Add some facts
        let fact1 = "My favorite language is Swift because of its safety."
        let fact2 = "The capital of France is Paris."
        let fact3 = "Swift runs natively on Apple Silicon."
        
        try memoryManager.addFact(content: fact1, vector: HolographicVector.encode(string: fact1))
        try memoryManager.addFact(content: fact2, vector: HolographicVector.encode(string: fact2))
        try memoryManager.addFact(content: fact3, vector: HolographicVector.encode(string: fact3))
        
        // Search for Swift
        let query = "Swift"
        let queryVector = HolographicVector.encode(string: query)
        let results = try memoryManager.search(query: query, queryVector: queryVector, limit: 5, threshold: 0.1)
        
        XCTAssertEqual(results.count, 2, "Should find 2 facts mentioning Swift")
        guard results.count >= 2 else { return }
        
        // The results should be ranked. fact1 and fact3.
        XCTAssertTrue(results[0].content.contains("Swift"))
        XCTAssertTrue(results[1].content.contains("Swift"))
    }
    
    func testPerformanceHolographicEncoding() throws {
        // Measure how fast HRR encoding runs
        let text = "This is a long sentence that we will use to test the performance of the NLTokenizer and Accelerate framework superposition."
        
        self.measure {
            _ = HolographicVector.encode(string: text)
        }
    }
    
    func testPerformanceSearch() throws {
        // Preload 100 facts
        for i in 0..<100 {
            let content = "Fact \(i): The system handles multiple queries concurrently."
            try memoryManager.addFact(content: content, vector: HolographicVector.encode(string: content))
        }
        // Preload 1 target fact
        let target = "Fact 101: The system runs on Apple Silicon."
        try memoryManager.addFact(content: target, vector: HolographicVector.encode(string: target))
        
        let query = "Apple Silicon"
        let queryVector = HolographicVector.encode(string: query)
        
        self.measure {
            _ = try? memoryManager.search(query: query, queryVector: queryVector, limit: 5)
        }
    }
}
