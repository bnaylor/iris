import Foundation
import GRDB

/// A structured fact stored in the SQLite Fact Store.
struct Fact: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    var id: String
    var content: String
    var category: String
    var entity: String?
    var tags: String?
    var trustScore: Double
    var timestamp: Date

    static let databaseTableName = "facts"

    init(
        id: String = UUID().uuidString,
        content: String,
        category: String = "general",
        entity: String? = nil,
        tags: String? = nil,
        trustScore: Double = 1.0,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.category = category
        self.entity = entity
        self.tags = tags
        self.trustScore = trustScore
        self.timestamp = timestamp
    }
}

/// Backward compatibility typealias
typealias HolographicFact = Fact

/// Legacy vector stub for backward compatibility
struct HolographicVector: Codable, Equatable, Sendable {
    static func encode(string: String, dimension: Int = 1024) -> HolographicVector { HolographicVector() }
    func encodedData() -> Data { Data() }
    func similarity(to other: HolographicVector) -> Float { 1.0 }
}

/// A relational edge connecting two facts in the Fact Store.
struct FactRelation: Codable, FetchableRecord, PersistableRecord, Sendable {
    var sourceId: String
    var targetId: String
    var relationType: String
    var weight: Double

    static let databaseTableName = "fact_relations"
}

/// Pure SQLite & FTS5 fact store replacing the legacy HRR vector implementation.
final class FactStoreManager: @unchecked Sendable {
    static let shared: FactStoreManager = {
        do {
            return try FactStoreManager()
        } catch {
            print("WARNING: FactStoreManager failed to initialize on disk. Falling back to in-memory mode. Error: \(error)")
            return try! FactStoreManager(inMemory: true)
        }
    }()

    private let dbPool: DatabasePool?
    let dbQueue: DatabaseQueue?

    init(inMemory: Bool = false, paths: IrisPaths = .default) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            db.trace { _ in } // Suppress logs by default
        }

        if inMemory {
            dbPool = nil
            dbQueue = try DatabaseQueue(configuration: configuration)
            try migrator.migrate(dbQueue!)
        } else {
            try? paths.ensureDirectories()
            let dbPath = paths.factStoreDB.path
            dbPool = try DatabasePool(path: dbPath, configuration: configuration)
            dbQueue = nil
            try migrator.migrate(dbPool!)
            try migrateLegacyHolographicFacts(paths: paths)
        }
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_fact_store") { db in
            try db.create(table: "facts") { t in
                t.column("id", .text).primaryKey()
                t.column("content", .text).notNull()
                t.column("category", .text).notNull().defaults(to: "general")
                t.column("entity", .text)
                t.column("tags", .text)
                t.column("trustScore", .double).notNull().defaults(to: 1.0)
                t.column("timestamp", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }

            try db.create(virtualTable: "facts_fts", using: FTS5()) { t in
                t.synchronize(withTable: "facts")
                t.column("content")
                t.column("category")
                t.column("entity")
                t.column("tags")
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

    /// Adds a fact to the SQLite Fact Store.
    @discardableResult
    func addFact(
        content: String,
        category: String = "general",
        entity: String? = nil,
        tags: String? = nil,
        trustScore: Double = 1.0
    ) throws -> Fact {
        let fact = Fact(
            content: content,
            category: category,
            entity: entity,
            tags: tags,
            trustScore: trustScore,
            timestamp: Date()
        )
        let writer: DatabaseWriter = dbQueue ?? dbPool!
        try writer.write { db in
            try fact.insert(db)
        }
        try? evictOldFacts()
        return fact
    }

    /// Backward compatibility overload ignoring legacy vector arguments.
    @discardableResult
    func addFact(content: String, vector: Any?, trustScore: Double = 1.0) throws -> Fact {
        return try addFact(content: content, trustScore: trustScore)
    }

    /// Searches facts using FTS5 full-text matching, trust weighting, and exponential time decay.
    func search(
        query: String,
        category: String? = nil,
        entity: String? = nil,
        limit: Int = 5,
        threshold: Double = 0.1
    ) throws -> [Fact] {
        let reader: DatabaseReader = dbQueue ?? dbPool!
        return try reader.read { db in
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let sanitizedQuery = sanitizeFTSQuery(trimmedQuery)

            let candidates: [Fact]
            if sanitizedQuery.isEmpty {
                candidates = try Fact.fetchAll(db, sql: "SELECT * FROM facts ORDER BY trustScore DESC, timestamp DESC LIMIT ?", arguments: [limit * 2])
            } else {
                let ftsPattern = FTS3Pattern(matchingAnyTokenIn: sanitizedQuery)
                var sql = """
                    SELECT facts.*
                    FROM facts
                    JOIN facts_fts ON facts_fts.rowid = facts.rowid
                    WHERE facts_fts MATCH ?
                    """
                var args: [DatabaseValueConvertible?] = [ftsPattern]

                if let category = category {
                    sql += " AND facts.category = ?"
                    args.append(category)
                }
                if let entity = entity {
                    sql += " AND facts.entity = ?"
                    args.append(entity)
                }

                candidates = try Fact.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            }

            let now = Date()
            let scored = candidates.compactMap { fact -> (Fact, Double)? in
                let ageInSeconds = now.timeIntervalSince(fact.timestamp)
                let ageInDays = max(0, ageInSeconds / 86400.0)
                let decayFactor = exp(-0.05 * ageInDays)
                let baseScore = 1.0 + (fact.trustScore * 0.1)
                let finalScore = baseScore * decayFactor

                if finalScore >= threshold {
                    return (fact, finalScore)
                }
                return nil
            }

            return scored
                .sorted { $0.1 > $1.1 }
                .prefix(limit)
                .map { $0.0 }
        }
    }

    /// Backward compatibility search overload ignoring legacy queryVector arguments.
    func search(query: String, queryVector: Any?, limit: Int = 5, threshold: Double = 0.1) throws -> [Fact] {
        return try search(query: query, limit: limit, threshold: threshold)
    }

    /// Retrieves all facts associated with a specific entity (probe).
    func probe(entity: String, limit: Int = 10) throws -> [Fact] {
        let reader: DatabaseReader = dbQueue ?? dbPool!
        return try reader.read { db in
            let sql = "SELECT * FROM facts WHERE entity = ? OR content LIKE ? ORDER BY trustScore DESC, timestamp DESC LIMIT ?"
            return try Fact.fetchAll(db, sql: sql, arguments: [entity, "%\(entity)%", limit])
        }
    }

    /// Reinforces facts by bumping trust score and updating timestamp.
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

    /// Removes a fact by ID.
    func removeFact(id: String) throws {
        let writer: DatabaseWriter = dbQueue ?? dbPool!
        try writer.write { db in
            _ = try Fact.deleteOne(db, key: id)
        }
    }

    /// Evicts old facts that have not been reinforced.
    func evictOldFacts() throws {
        let writer: DatabaseWriter = dbQueue ?? dbPool!
        try writer.write { db in
            let sql = """
                DELETE FROM facts 
                WHERE ((julianday('now') - julianday(timestamp)) > 30 AND trustScore < 1.2)
                OR ((julianday('now') - julianday(timestamp)) > 90)
                """
            try db.execute(sql: sql)
        }
    }

    /// Migrate legacy facts from holographic_memory.sqlite if present.
    private func migrateLegacyHolographicFacts(paths: IrisPaths) throws {
        let fm = FileManager.default
        let legacyDBPath = paths.holographicDB.path
        guard fm.fileExists(atPath: legacyDBPath) else { return }

        let writer: DatabaseWriter = dbQueue ?? dbPool!
        let hasFacts = try writer.read { db in
            try Fact.fetchCount(db) > 0
        }
        guard !hasFacts else { return }

        if let legacyQueue = try? DatabaseQueue(path: legacyDBPath) {
            try legacyQueue.read { legacyDB in
                if try legacyDB.tableExists("facts") {
                    let rows = try Row.fetchAll(legacyDB, sql: "SELECT id, content, trustScore, timestamp FROM facts")
                    try writer.write { db in
                        for row in rows {
                            if let id: String = row["id"], let content: String = row["content"] {
                                let trustScore: Double = row["trustScore"] ?? 1.0
                                let timestamp: Date = row["timestamp"] ?? Date()
                                let fact = Fact(id: id, content: content, category: "general", trustScore: trustScore, timestamp: timestamp)
                                try fact.insert(db)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Sanitizes FTS query input by replacing special characters.
    private func sanitizeFTSQuery(_ query: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        return query.unicodeScalars
            .filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
    }
}

/// Backward compatibility alias
typealias HolographicMemoryManager = FactStoreManager
