# Open Knowledge Format (OKF) Memory Architecture

Iris eschews proprietary databases and opaque JSON blobs for its memory layer. Instead, it fully adopts the **[Open Knowledge Format (OKF)](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing)**, an open, vendor-neutral specification that structures organizational knowledge so it is highly accessible to both LLMs and humans.

## Why OKF?

The core premise of OKF is the "LLM-wiki" pattern:
1. **Vendor Neutrality:** Memory is simply a directory of Markdown files. It can be hosted on Git, edited in Obsidian or VSCode, and read by any system.
2. **Readability:** Information remains perfectly legible to human users without needing specialized query tools.
3. **Agent Accessibility:** The standardized YAML frontmatter allows programmatic parsing, semantic vector ingestion, and strict classification.

---

## The Structure

Every file in the Iris memory layer (`~/.iris/skills/*`, `~/.iris/USER.md`, `~/.iris/SOUL.md`) MUST be an OKF-compliant Markdown document. 

### YAML Frontmatter
Each file begins with a strict YAML metadata block bounded by `---`.

```yaml
---
type: [skill | profile | core | project]
title: "A short, descriptive title"
description: "A 1-2 sentence summary of the file's purpose"
tags: [tag1, tag2, tag3]
timestamp: "2026-07-10T12:00:00Z"
---
```

*   **`type` (Required by OKF spec):** Defines the ontological category of the document.
*   **`title` / `description`:** Aids the `HolographicMemoryManager` in generating high-quality vector embeddings.
*   **`tags`:** Enables fast categorical filtering before vector search.
*   **`timestamp`:** Essential for the `/reflect` grooming loop to prune stale knowledge.

### The Knowledge Graph (Cross-linking)

Instead of maintaining a massive relational schema in SQLite, Iris builds a localized knowledge graph using standard Markdown links.

When Iris learns a user preference about a specific project, it doesn't just append it to a global `USER.md`. It links them:
`"User prefers to use [Vibecop](file:///Users/username/.iris/vibecop.md) for security guarding."`

---

## Memory Maintenance & Grooming

A common failure mode for agent memory is unbounded append-only growth, leading to contradictory context. Iris solves this with autonomous grooming.

### The `/reflect` Loop
When the `/reflect` trigger fires (either manually or via the autonomous interval), Iris executes a **grooming pass** over the Markdown library:
1. **Schema Enforcement:** It verifies that all files possess valid OKF frontmatter and writes missing fields.
2. **Link Integrity:** It checks the file paths in Markdown links to ensure cross-links between concepts are still valid.
3. **Consolidation:** It merges redundant files and reorganizes the folder hierarchy if it detects semantic drift.
