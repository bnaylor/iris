import Foundation

/// One-shot migration of an old flat `~/.iris` layout to the segregated
/// `memory/` + `config/` + `models/` layout.
///
/// Idempotent and non-destructive: each file moves only if the source exists and the
/// destination does not, so re-runs and partially-migrated installs are safe. The one
/// sanctioned deletion is the redundant stray `~/.iris/SOUL.md` (the never-read copy), removed
/// only once the canonical `memory/SOUL.md` is in place. Must run before any manager opens a
/// migrated file (notably the holographic SQLite DB — moving an open WAL database corrupts it).
enum IrisMigrator {
    static func migrate(_ paths: IrisPaths) {
        let fm = FileManager.default
        try? paths.ensureDirectories()
        let root = paths.root

        // memory/ files
        moveIfNeeded(fm, from: root.appendingPathComponent("USER.md"), to: paths.userMd)
        moveIfNeeded(fm, from: root.appendingPathComponent("memory.md"), to: paths.memoryMd)
        moveIfNeeded(fm, from: root.appendingPathComponent("skills"), to: paths.skillsDir)
        moveIfNeeded(fm, from: root.appendingPathComponent("library"), to: paths.artifactsDir)

        // holographic DB + WAL sidecars
        moveIfNeeded(fm, from: root.appendingPathComponent("holographic_memory.sqlite"), to: paths.holographicDB)
        moveIfNeeded(fm, from: root.appendingPathComponent("holographic_memory.sqlite-shm"),
                     to: paths.memoryDir.appendingPathComponent("holographic_memory.sqlite-shm"))
        moveIfNeeded(fm, from: root.appendingPathComponent("holographic_memory.sqlite-wal"),
                     to: paths.memoryDir.appendingPathComponent("holographic_memory.sqlite-wal"))

        // config/ files
        moveIfNeeded(fm, from: root.appendingPathComponent("settings.json"), to: paths.settingsJSON)
        moveIfNeeded(fm, from: root.appendingPathComponent("permissions.json"), to: paths.permissionsJSON)
        moveIfNeeded(fm, from: root.appendingPathComponent("mcp_servers.json"), to: paths.mcpServersJSON)

        // SOUL: the actively-read prompts/SOUL.md is canonical; the stray root SOUL.md is the
        // redundant never-read copy and is deleted once the canonical one exists.
        moveIfNeeded(fm, from: root.appendingPathComponent("prompts/SOUL.md"), to: paths.soulMd)
        let straySoul = root.appendingPathComponent("SOUL.md")
        if fm.fileExists(atPath: paths.soulMd.path), fm.fileExists(atPath: straySoul.path) {
            try? fm.removeItem(at: straySoul)
        }
    }

    /// Move only when the source exists and the destination does not — idempotent and never
    /// overwrites an already-migrated file.
    private static func moveIfNeeded(_ fm: FileManager, from: URL, to: URL) {
        guard fm.fileExists(atPath: from.path) else { return }

        var fromIsDir: ObjCBool = false
        let fromExists = fm.fileExists(atPath: from.path, isDirectory: &fromIsDir)
        guard fromExists else { return }

        var toIsDir: ObjCBool = false
        let toExists = fm.fileExists(atPath: to.path, isDirectory: &toIsDir)

        if toExists {
            // If destination exists and is a directory, check if it's empty
            if toIsDir.boolValue {
                let contents = try? fm.contentsOfDirectory(at: to, includingPropertiesForKeys: nil)
                if let contents = contents, !contents.isEmpty {
                    return  // Don't overwrite non-empty destination
                }
                // Destination is an empty directory; move source's contents into it
                if fromIsDir.boolValue {
                    moveDirectoryContents(fm, from: from, to: to)
                    try? fm.removeItem(at: from)
                }
                return
            } else {
                // Destination file exists, don't overwrite
                return
            }
        }

        // Destination doesn't exist; perform normal move
        try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.moveItem(at: from, to: to)
    }

    /// Move all contents from source directory to destination directory.
    private static func moveDirectoryContents(_ fm: FileManager, from: URL, to: URL) {
        guard let contents = try? fm.contentsOfDirectory(at: from, includingPropertiesForKeys: nil) else {
            return
        }
        for item in contents {
            let dest = to.appendingPathComponent(item.lastPathComponent)
            try? fm.moveItem(at: item, to: dest)
        }
    }
}
