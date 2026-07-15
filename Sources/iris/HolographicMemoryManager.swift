import Foundation
import GRDB
import Accelerate
import NaturalLanguage

/// A pure-Swift implementation of Holographic Reduced Representations (HRR).
/// Encodes factual context into fixed-dimensional vectors for semantic retrieval without Python or NumPy.
struct HolographicVector: Codable, Equatable {
    let dimension: Int
    var values: [Float]
    
    init(dimension: Int = 1024, values: [Float]? = nil) {
        self.dimension = dimension
        if let values = values {
            assert(values.count == dimension)
            self.values = values
        } else {
            // Initialize with standard normal distribution (mean 0, variance 1/N)
            self.values = [Float](repeating: 0, count: dimension)
            let scale = Float(1.0 / sqrt(Double(dimension)))
            for i in 0..<dimension {
                let u1 = Float.random(in: 0.000001...1)
                let u2 = Float.random(in: 0...1)
                let z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
                self.values[i] = z0 * scale
            }
        }
    }
    
    /// Deterministically generates a vector for a single token using its hash as a random seed.
    init(token: String, dimension: Int = 1024) {
        self.dimension = dimension
        self.values = [Float](repeating: 0, count: dimension)
        var hasher = Hasher()
        hasher.combine(token)
        let seed = UInt64(bitPattern: Int64(hasher.finalize()))
        
        // Simple LCG for deterministic generation
        var state = seed
        func nextRandom() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let max = Float(UInt64.max)
            return Float(state) / max
        }
        
        let scale = Float(1.0 / sqrt(Double(dimension)))
        for i in 0..<dimension {
            let u1 = max(0.000001, nextRandom())
            let u2 = nextRandom()
            let z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
            self.values[i] = z0 * scale
        }
    }
    
    /// Encodes a full string into a Holographic Vector by tokenizing and superposing.
    static func encode(string: String, dimension: Int = 1024) -> HolographicVector {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = string
        var combined = HolographicVector(dimension: dimension, values: [Float](repeating: 0, count: dimension))
        
        tokenizer.enumerateTokens(in: string.startIndex..<string.endIndex) { tokenRange, _ in
            let token = String(string[tokenRange]).lowercased()
            let tokenVector = HolographicVector(token: token, dimension: dimension)
            combined = combined.superposed(with: tokenVector)
            return true
        }
        
        // Normalize the final vector
        var result = [Float](repeating: 0, count: dimension)
        var norm: Float = 0
        vDSP_svesq(combined.values, 1, &norm, vDSP_Length(dimension))
        norm = sqrt(norm)
        if norm > 0 {
            vDSP_vsdiv(combined.values, 1, &norm, &result, 1, vDSP_Length(dimension))
        }
        return HolographicVector(dimension: dimension, values: result)
    }
    
    /// Binds this vector with another using circular convolution.
    func bound(with other: HolographicVector) -> HolographicVector {
        assert(self.dimension == other.dimension)
        var result = [Float](repeating: 0, count: dimension)
        
        // Use vDSP for circular convolution via FFT
        // Since N=1024 is small, an O(N^2) convolution is also fine but FFT is ideal.
        // For simplicity and dependency-free, here is the raw circular convolution:
        for i in 0..<dimension {
            var sum: Float = 0
            for j in 0..<dimension {
                let k = (i - j + dimension) % dimension
                sum += self.values[j] * other.values[k]
            }
            result[i] = sum
        }
        
        return HolographicVector(dimension: dimension, values: result)
    }
    
    /// Superposes this vector with another (element-wise addition).
    func superposed(with other: HolographicVector) -> HolographicVector {
        assert(self.dimension == other.dimension)
        var result = [Float](repeating: 0, count: dimension)
        vDSP_vadd(self.values, 1, other.values, 1, &result, 1, vDSP_Length(dimension))
        return HolographicVector(dimension: dimension, values: result)
    }
    
    /// Computes similarity with another vector (dot product).
    func similarity(to other: HolographicVector) -> Float {
        assert(self.dimension == other.dimension)
        var dot: Float = 0
        vDSP_dotpr(self.values, 1, other.values, 1, &dot, vDSP_Length(dimension))
        return dot
    }
    
    func encodedData() -> Data {
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
    
    static func decoded(from data: Data, dimension: Int = 1024) -> HolographicVector {
        let count = data.count / MemoryLayout<Float>.stride
        assert(count == dimension)
        var values = [Float](repeating: 0, count: count)
        _ = values.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return HolographicVector(dimension: dimension, values: values)
    }
}

/// A fact stored in the JIT Memory layer.
struct HolographicFact: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var content: String
    var hrrVectorData: Data
    var trustScore: Double
    var timestamp: Date
    
    static let databaseTableName = "facts"
    
    var vector: HolographicVector {
        get { HolographicVector.decoded(from: hrrVectorData) }
        set { hrrVectorData = newValue.encodedData() }
    }
}

/// A relational edge connecting two facts.
struct FactRelation: Codable, FetchableRecord, PersistableRecord {
    var sourceId: String
    var targetId: String
    var relationType: String
    var weight: Double
    
    static let databaseTableName = "fact_relations"
}

/// Manages the local SQLite database for holographic memory using GRDB.
final class HolographicMemoryManager: @unchecked Sendable {
    static let shared: HolographicMemoryManager = {
        do {
            return try HolographicMemoryManager()
        } catch {
            print("WARNING: HolographicMemoryManager failed to initialize on disk. Falling back to in-memory mode. Error: \(error)")
            return try! HolographicMemoryManager(inMemory: true)
        }
    }()
    
    private let dbPool: DatabasePool?
    
    // For tests that want an in-memory database
    let dbQueue: DatabaseQueue?
    
    init(inMemory: Bool = false) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            db.trace { _ in } // Suppress logs by default
        }
        
        if inMemory {
            dbPool = nil
            dbQueue = try DatabaseQueue(configuration: configuration)
            try migrator.migrate(dbQueue!)
        } else {
            try? IrisPaths.default.ensureDirectories()
            let dbPath = IrisPaths.default.holographicDB.path
            dbPool = try DatabasePool(path: dbPath, configuration: configuration)
            dbQueue = nil
            try migrator.migrate(dbPool!)
        }
    }
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1") { db in
            try db.create(table: "facts") { t in
                t.column("id", .text).primaryKey()
                t.column("content", .text).notNull()
                t.column("hrrVectorData", .blob).notNull()
                t.column("trustScore", .double).notNull().defaults(to: 1.0)
                t.column("timestamp", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
            
            try db.create(virtualTable: "facts_fts", using: FTS5()) { t in
                t.synchronize(withTable: "facts")
                t.column("content")
            }
            
            try db.create(table: "fact_relations") { t in
                t.column("sourceId", .text).references("facts", column: "id", onDelete: .cascade)
                t.column("targetId", .text).references("facts", column: "id", onDelete: .cascade)
                t.column("relationType", .text)
                t.column("weight", .double).notNull().defaults(to: 1.0)
                t.primaryKey(["sourceId", "targetId"])
            }
        }
        
        return migrator
    }
    
    func addFact(content: String, vector: HolographicVector, trustScore: Double = 1.0) throws {
        let fact = HolographicFact(
            id: UUID().uuidString,
            content: content,
            hrrVectorData: vector.encodedData(),
            trustScore: trustScore,
            timestamp: Date()
        )
        if let queue = dbQueue {
            try queue.write { db in try fact.insert(db) }
        } else if let pool = dbPool {
            try pool.write { db in try fact.insert(db) }
        }
        
        // Evict old unused facts occasionally when adding new ones
        try? evictOldFacts()
    }
    
    func search(query: String, queryVector: HolographicVector, limit: Int = 5, threshold: Float = 0.3) throws -> [HolographicFact] {
        let reader: DatabaseReader = dbQueue ?? dbPool!
        return try reader.read { db in
            // Step 1: Lexical filtering via FTS5
            let ftsPattern = FTS3Pattern(matchingAnyTokenIn: query)
            let sql = """
                SELECT facts.*
                FROM facts
                JOIN facts_fts ON facts_fts.rowid = facts.rowid
                WHERE facts_fts MATCH ?
                """
            let candidates = try HolographicFact.fetchAll(db, sql: sql, arguments: [ftsPattern])
            
            // Step 2: Semantic Ranking in Swift with Time Decay
            let now = Date()
            let scored = candidates.compactMap { fact -> (HolographicFact, Float)? in
                let sim = fact.vector.similarity(to: queryVector)
                let baseScore = sim + Float(fact.trustScore * 0.1)
                
                // Calculate age in days
                let ageInSeconds = now.timeIntervalSince(fact.timestamp)
                let ageInDays = max(0, ageInSeconds / 86400.0)
                
                // Exponential decay (half-life of ~14 days if not reinforced)
                let decayFactor = Float(exp(-0.05 * ageInDays))
                let decayedScore = baseScore * decayFactor
                
                if decayedScore >= threshold {
                    return (fact, decayedScore)
                }
                return nil
            }
            
            return scored
                .sorted { $0.1 > $1.1 }
                .prefix(limit)
                .map { $0.0 }
        }
    }
    
    /// Reinforces facts by bumping their trust score and resetting their timestamp, keeping them fresh.
    func reinforceFacts(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let writer: DatabaseWriter = dbQueue ?? dbPool!
        try writer.write { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let sql = """
                UPDATE facts
                SET timestamp = CURRENT_TIMESTAMP,
                    trustScore = trustScore + 0.1
                WHERE id IN (\(placeholders))
                """
            try db.execute(sql: sql, arguments: StatementArguments(ids))
        }
    }
    
    /// Garbage collection for facts that haven't been reinforced recently and have low trust
    func evictOldFacts() throws {
        let writer: DatabaseWriter = dbQueue ?? dbPool!
        try writer.write { db in
            // Delete facts older than 30 days that have never been significantly reinforced (trustScore < 1.2),
            // OR facts that are older than 90 days regardless of trust score to prevent unbounded growth.
            let sql = """
                DELETE FROM facts 
                WHERE ((julianday('now') - julianday(timestamp)) > 30 AND trustScore < 1.2)
                OR ((julianday('now') - julianday(timestamp)) > 90)
                """
            try db.execute(sql: sql)
        }
    }
}
