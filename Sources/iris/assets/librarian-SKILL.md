---
name: librarian
description: Basic file and workspace organization guidelines. Enforces clean directory structures, sensible naming, and repository hygiene across workspaces.
type: skill
timestamp: 2026-07-30T00:00:00Z
---

# Librarian — Workspace & File Organization

## Overview
Agents frequently drop new files, temporary scripts, and unformatted documents directly into the root `./` directory of active workspaces. This skill establishes clear, repeatable file organization and workspace hygiene guidelines for Iris.

## Core Rules & Hygiene

### 1. Repository Management & Clones
- Always clone or initialize source repositories under `~/src/<repo-name>` or `~/work/<repo-name>`.
- Never initialize git repositories directly in `$HOME` or random temporary root folders.

### 2. Workspace Subdirectory Structure
Keep workspace root directories clean. Organize files into dedicated subdirectories based on their function:
- **`src/` or `Sources/`**: Application source code and implementation modules.
- **`docs/`**: Documentation, architecture guides, and specs.
- **`scripts/`**: Automation scripts, utility tools, and helper commands.
- **`tests/` or `Tests/`**: Test suites, test fixtures, and mock datasets.
- **`assets/`**: Static media, templates, schemas, and bundled binary resources.

### 3. Documentation Conventions
Store design artifacts and reviews strictly in date-prefixed kebab-case files under `docs/`:
- **Design Specs**: `docs/specs/YYYY-MM-DD-feature-name.md`
- **Implementation Plans**: `docs/plans/YYYY-MM-DD-feature-name.md`
- **Peer & Architecture Reviews**: `docs/reviews/YYYY-MM-DD-feature-name-review.md`

### 4. No Loose Root Files ("No Ants")
- Do NOT write generic temporary scripts (`test.py`, `script.sh`, `temp.md`, `foo.txt`) into root `./`.
- If a temporary script is necessary for verification, write it under `scripts/` or a workspace-scoped `tmp/` directory, and clean it up when completed.
- Descriptive naming is required: use meaningful, self-documenting file names (e.g., `validate-schema.py`, `export-metrics.sh`).

## Summary Checklist Before Writing Files
1. Am I writing to a dedicated subdirectory (`src/`, `docs/`, `scripts/`, `tests/`) rather than workspace root?
2. Does the file name describe its exact purpose without ambiguity?
3. If this is a spec, plan, or review, is it placed under `docs/specs/`, `docs/plans/`, or `docs/reviews/` with a `YYYY-MM-DD-` date prefix?
