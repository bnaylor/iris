# Building & Releasing Iris

This guide covers developer instructions for building signed production release packages for macOS and publishing them to GitHub Releases.

## Build & Release Script

Iris includes a native release packaging script located at [`scripts/build_release.sh`](file:///Users/bnaylor/src/iris/scripts/build_release.sh).

### Quick Start

To compile and build a release `.app` bundle, `.zip` archive, and SHA256 checksum:

```bash
./scripts/build_release.sh v0.2.0
```

Artifacts are produced in `.build/release/`:
- `Iris-v0.2.0-macOS.zip`
- `Iris-v0.2.0-macOS.zip.sha256`

---

## Publishing to GitHub Releases

To automatically build, package, and publish a release tag to GitHub:

```bash
./scripts/build_release.sh v0.2.0 --publish
```

---

## Including Release Notes

You can supply release notes in one of three ways:

### Option 1: Via Environment Variable
Pass inline release notes using the `RELEASE_NOTES` environment variable:

```bash
RELEASE_NOTES="### What's New
- Added auto-updater in Settings.
- Improved subagent VM container configuration.
- Fixed scroll cursor jumps." ./scripts/build_release.sh v0.2.0 --publish
```

### Option 2: Via Release Notes File (`RELEASE_NOTES.md`)
Create a `RELEASE_NOTES.md` file in the repo root (or `docs/RELEASE_NOTES.md`). The release script will automatically detect and attach it to the GitHub Release:

```bash
echo "## Iris v0.2.0 Release Highlights..." > RELEASE_NOTES.md
./scripts/build_release.sh v0.2.0 --publish
```

### Option 3: Automatic Release Notes (`--generate-notes`)
If no release notes variable or file is provided, the script automatically passes `--generate-notes` to GitHub CLI (`gh`), which generates release notes automatically based on merged commits and PRs.

---

## Code Signing & Developer ID

By default, the release script performs ad-hoc code signing (`-s "-"`). To sign with an official Apple Developer ID certificate:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build_release.sh v0.2.0 --publish
```
