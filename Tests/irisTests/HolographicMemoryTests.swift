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
    
    func testReinforceFacts() throws {
        let fact1 = "My favorite language is Swift because of its safety."
        try memoryManager.addFact(content: fact1, vector: HolographicVector.encode(string: fact1))
        
        let results1 = try memoryManager.search(query: "Swift", queryVector: HolographicVector.encode(string: "Swift"), limit: 1, threshold: 0.0)
        XCTAssertEqual(results1.count, 1)
        let initialTrust = results1[0].trustScore
        
        try memoryManager.reinforceFacts(ids: [results1[0].id])
        
        let results2 = try memoryManager.search(query: "Swift", queryVector: HolographicVector.encode(string: "Swift"), limit: 1, threshold: 0.0)
        XCTAssertEqual(results2.count, 1)
        XCTAssertGreaterThan(results2[0].trustScore, initialTrust)
    }
    
    func testEvictOldFacts() throws {
        let writer: GRDB.DatabaseWriter = memoryManager.dbQueue!
        
        // Add a fact with old timestamp
        try writer.write { db in
            let factId = UUID().uuidString
            let sql = """
                INSERT INTO facts (id, content, hrrVectorData, trustScore, timestamp)
                VALUES (?, 'Old fact', ?, 1.0, datetime('now', '-40 days'))
                """
            try db.execute(sql: sql, arguments: [factId, HolographicVector.encode(string: "Old fact").encodedData()])
        }
        
        try memoryManager.evictOldFacts()
        
        let results = try memoryManager.search(query: "Old", queryVector: HolographicVector.encode(string: "Old"), limit: 1, threshold: 0.0)
        XCTAssertEqual(results.count, 0, "Old fact should be evicted")
    }
    
    func testTimeDecayRanking() throws {
        let writer: GRDB.DatabaseWriter = memoryManager.dbQueue!
        
        // Add two identical facts, one old, one new
        let query = "Time decay test"
        let vectorData = HolographicVector.encode(string: query).encodedData()
        
        try writer.write { db in
            let sql1 = """
                INSERT INTO facts (id, content, hrrVectorData, trustScore, timestamp)
                VALUES (?, 'Time decay test fact', ?, 1.0, datetime('now', '-10 days'))
                """
            try db.execute(sql: sql1, arguments: [UUID().uuidString, vectorData])
            
            let sql2 = """
                INSERT INTO facts (id, content, hrrVectorData, trustScore, timestamp)
                VALUES (?, 'Time decay test fact', ?, 1.0, datetime('now'))
                """
            try db.execute(sql: sql2, arguments: [UUID().uuidString, vectorData])
        }
        
        let results = try memoryManager.search(query: "decay", queryVector: HolographicVector.encode(string: "decay"), limit: 2, threshold: 0.0)
        XCTAssertEqual(results.count, 2)
        
        // The newer one should be ranked first due to decay
        let age0 = Date().timeIntervalSince(results[0].timestamp)
        let age1 = Date().timeIntervalSince(results[1].timestamp)
        XCTAssertLessThan(age0, age1, "Newer fact should be ranked higher")
    }
}
