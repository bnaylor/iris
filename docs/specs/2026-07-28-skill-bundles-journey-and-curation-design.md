# Design Spec: Skill Bundles, Journey Timeline & Autonomous Curator

* **Issue**: [#44](https://github.com/bnaylor/iris/issues/44) - Further tweaks to skill-curation
* **Date**: 2026-07-28
* **Status**: Approved

---

## 1. Overview & Goals

To continue building Iris into a self-improving, highly responsive agent harness, this spec introduces three major enhancements inspired by Hermes Agent:

1. **Skill Bundles:** Define named groups of skills (e.g. `devops = ["k8s-debug", "gke-provision", "spanner-perf"]`) stored in `~/.iris/memory/bundles.json`. Activating a bundle via `/bundle <name>` loads all grouped skills at once into the session and invalidates the system prompt cache.
2. **`/journey` Learning Timeline:** A deterministic slash command that scans OKF timestamps across `USER.md`, `SOUL.md`, `skills/*`, and `FactStoreManager` to display a chronological, interactive timeline of everything Iris has learned.
3. **Autonomous Skill Curator (`SkillCurator.swift` & `/skills curate`):** A curation engine that evaluates skills against an OKF quality rubric, consolidates duplicate skills, prunes dead/empty skills, and outputs a per-run curation report to `~/.iris/memory/curator/REPORT.md`.

---

## 2. Component Architecture

### A. Skill Bundles (`SkillBundleManager.swift` & `/bundle`)
* **Storage:** `~/.iris/memory/bundles.json` mapping bundle names to arrays of skill names.
* **Command:** `/bundle` (list bundles), `/bundle save <name> <skill1,skill2,...>` (create/update bundle), `/bundle <name>` (activate all skills in bundle).
* **Auto-Complete:** `SlashCommandItem` auto-suggests defined bundles.

### B. `/journey` Timeline Generator (`JourneyManager.swift`)
* **Scanner:** Reads `timestamp:` YAML frontmatter across `~/.iris/memory/USER.md`, `~/.iris/memory/SOUL.md`, `~/.iris/memory/skills/*/SKILL.md`, and top records from `FactStoreManager`.
* **Output:** Sorts chronologically and outputs a clean Markdown timeline with category badges (`[Skill]`, `[Profile]`, `[Core]`, `[Fact]`) and timestamps.

### C. Skill Curator (`SkillCurator.swift` & `/skills curate`)
* **Rubric:**
  - **Validity:** Valid OKF YAML frontmatter (`name`, `description`, `type: skill`, `timestamp`).
  - **Non-Emptiness:** Body contains >20 characters and actual steps/commands.
  - **Uniqueness:** Checks for duplicate/overlapping skill names or descriptions.
* **Actions:**
  - **Prune:** Removes empty or corrupt skill folders.
  - **Report:** Writes a structured Markdown report to `~/.iris/memory/curator/REPORT.md` listing active skills, pruned skills, and recommendations.

---

## 3. Detailed Data Models

```swift
public struct SkillBundle: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let skillNames: [String]
}

public struct JourneyItem: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let category: String // "skill", "profile", "soul", "fact"
    public let timestamp: Date
    public let summary: String
    public let path: String?
}
```

---

## 4. Testing & Verification

1. Unit tests for `SkillBundleManager` (create, load, activate, JSON persistence).
2. Unit tests for `JourneyManager` (scanning OKF frontmatter timestamps and sorting).
3. Unit tests for `SkillCurator` (pruning empty skills and generating `REPORT.md`).
