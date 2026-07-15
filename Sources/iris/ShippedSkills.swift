import Foundation

/// Seeds shipped default content (currently the library skill + library README) into an
/// install if absent. Idempotent and non-destructive: a file is written only when missing, so
/// bot edits are preserved and a deliberately deleted file re-seeds on the next launch. Runs at
/// startup after `IrisMigrator`, so it seeds into the already-migrated `memory/` layout. Once
/// seeded, the library skill is picked up by the existing `SkillManager.discoverSkills()`.
enum ShippedSkills {

    /// Production entry point: reads the bundled assets and seeds them.
    static func seedIfNeeded(_ paths: IrisPaths) {
        seed(into: paths,
             librarySkill: bundledText("library-SKILL"),
             libraryReadme: bundledText("library-README"))
    }

    /// Testable core: seeds the provided contents, per-file seed-if-absent. An empty string
    /// skips that item (e.g. a bundle asset that failed to load).
    static func seed(into paths: IrisPaths, librarySkill: String, libraryReadme: String) {
        try? paths.ensureDirectories()
        let fm = FileManager.default

        if !librarySkill.isEmpty {
            let skillDir = paths.skillsDir.appendingPathComponent("library")
            let skillFile = skillDir.appendingPathComponent("SKILL.md")
            if !fm.fileExists(atPath: skillFile.path) {
                try? fm.createDirectory(at: skillDir, withIntermediateDirectories: true)
                try? librarySkill.write(to: skillFile, atomically: true, encoding: .utf8)
            }
        }

        if !libraryReadme.isEmpty {
            let readmeFile = paths.libraryDir.appendingPathComponent("README.md")
            if !fm.fileExists(atPath: readmeFile.path) {
                try? libraryReadme.write(to: readmeFile, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Read a bundled markdown asset by resource name (no extension). Returns "" if missing so a
    /// packaging error skips seeding rather than crashing.
    static func bundledText(_ resource: String) -> String {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return text
    }
}
