# Agent instructions

## git hygiene 
- always commit when we get something accomplished and reach a natural transition point, or stopping point
- give yourself co-credit (gemini, claude, etc)
- use conventional commits
- add things to .gitignore liberally - build products, temp files, etc.  don't commit giant blobs 

## context
- if you need to save memories, do it aggressively

## currency
- always update the README.md when major things change - new features, adjustments, etc
- Add docs to docs/ as necessary. Especially when adding new features, what would we want to tell someone about how to use them?
- Add unit tests when introducing new function whenever practical
- Run unit tests before commit and ensure that they pass.

## Definition of Done (Atomic Feature Check)
Before opening or updating a Pull Request, verify:
1. **Docs Currency:** Every new user-facing feature, slash command, configuration key, or CLI flag MUST have its corresponding entries added to `README.md` and reference guides in `docs/` in the same commit. Never wait for the user to ask if docs exist.
2. **Automated Verification:** Unit tests exist under `Tests/` and cover all newly added features and edge cases.
3. **Spec, Plan & Review Layout:** Design specs live in `docs/specs/YYYY-MM-DD-feature-name.md`, implementation plans in `docs/plans/YYYY-MM-DD-feature-name.md`, and reviews in `docs/reviews/YYYY-MM-DD-feature-name-review.md`.

## Specs, Plans & Reviews Layout
- **Design Specs:** Save to `docs/specs/YYYY-MM-DD-feature-name.md`.
- **Implementation Plans:** Save to `docs/plans/YYYY-MM-DD-feature-name.md`.
- **Peer & Architecture Reviews:** Save to `docs/reviews/YYYY-MM-DD-feature-name-review.md`.
- Do NOT save specs, plans, or reviews under `superpowers/`. Always enforce `docs/specs/`, `docs/plans/`, and `docs/reviews/` as the canonical directories with date-prefixed filenames (`YYYY-MM-DD-feature-name.md`).

