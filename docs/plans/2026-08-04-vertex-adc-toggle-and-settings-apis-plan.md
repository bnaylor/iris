# Automatic Vertex AI ADC Toggle & Expanded Settings GCP APIs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically route Gemini requests to the Global Vertex AI endpoint when ADC auth mode is selected and expand Settings to let users enable Vertex AI, Cloud AI Companion, and Gemini APIs.

**Architecture:** Update `GCloudHelper.requiredAPIs` to include the 3 AI APIs for automatic Settings enablement, and update `LLMClient.swift` (`generateContent` and `endpoint(for:)`) to automatically resolve to `https://aiplatform.googleapis.com/v1/projects/<project>/locations/global/publishers/google/models/<model>:generateContent` when ADC is selected and base URL is not overridden.

**Tech Stack:** Swift, macOS, Google Cloud (Vertex AI, ADC, gcloud CLI), XCTest

## Global Constraints

* Target Global Vertex AI endpoint (`aiplatform.googleapis.com/v1/projects/<project>/locations/global/...`) when ADC mode is active and `geminiBaseURL` is empty.
* Support modern Gemini models natively on the Global shard without model down-mapping.
* Expand `GCloudHelper.requiredAPIs` from 6 to 9 APIs (`aiplatform.googleapis.com`, `cloudaicompanion.googleapis.com`, `generativelanguage.googleapis.com`).

---

### Task 1: Expand Required GCP APIs in `GCloudHelper.swift` and Update `GCloudHelperTests.swift`

**Files:**
- Modify: `Sources/iris/GCloudHelper.swift:20-30`
- Modify: `Tests/irisTests/GCloudHelperTests.swift:8-60`

**Interfaces:**
- Consumes: `GCloudHelper.APIInfo` struct definition
- Produces: 9 elements in `GCloudHelper.requiredAPIs` including `aiplatform.googleapis.com`, `cloudaicompanion.googleapis.com`, and `generativelanguage.googleapis.com`.

- [ ] **Step 1: Write the failing test in `Tests/irisTests/GCloudHelperTests.swift`**

Replace lines 8-50 in `Tests/irisTests/GCloudHelperTests.swift` with the following test assertions:

```swift
    func testRequiredAPIsCount() {
        XCTAssertEqual(GCloudHelper.requiredAPIs.count, 9, "Nine APIs should be defined (6 Workspace + 3 Google Cloud AI APIs)")
    }
    
    func testRequiredAPIsUniqueIDs() {
        let ids = GCloudHelper.requiredAPIs.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "API service names must be unique")
    }
    
    func testRequiredAPIIDsAreCorrect() {
        let ids = Set(GCloudHelper.requiredAPIs.map(\.id))
        XCTAssertTrue(ids.contains("calendar-json.googleapis.com"))
        XCTAssertTrue(ids.contains("drive.googleapis.com"))
        XCTAssertTrue(ids.contains("docs.googleapis.com"))
        XCTAssertTrue(ids.contains("sheets.googleapis.com"))
        XCTAssertTrue(ids.contains("gmail.googleapis.com"))
        XCTAssertTrue(ids.contains("tasks.googleapis.com"))
        XCTAssertTrue(ids.contains("aiplatform.googleapis.com"))
        XCTAssertTrue(ids.contains("cloudaicompanion.googleapis.com"))
        XCTAssertTrue(ids.contains("generativelanguage.googleapis.com"))
        XCTAssertFalse(ids.contains("people.googleapis.com"))
    }
    
    func testRequiredAPIScopesAreCorrect() {
        let scopes = Set(GCloudHelper.requiredAPIs.map(\.scope))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/calendar"))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/drive"))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/documents"))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/spreadsheets"))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/gmail.modify"))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/tasks"))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/cloud-platform"))
        XCTAssertTrue(scopes.contains("https://www.googleapis.com/auth/generative-language"))
    }
    
    func testRequiredAPIDisplayNames() {
        let names = GCloudHelper.requiredAPIs.map(\.displayName)
        XCTAssertTrue(names.contains("Google Calendar"))
        XCTAssertTrue(names.contains("Google Drive"))
        XCTAssertTrue(names.contains("Google Docs"))
        XCTAssertTrue(names.contains("Google Sheets"))
        XCTAssertTrue(names.contains("Gmail"))
        XCTAssertTrue(names.contains("Google Tasks"))
        XCTAssertTrue(names.contains("Vertex AI"))
        XCTAssertTrue(names.contains("Cloud AI Companion"))
        XCTAssertTrue(names.contains("Gemini API"))
        XCTAssertFalse(names.contains("Google People"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GCloudHelperTests`  
Expected: FAIL with `XCTAssertEqual failed: ("6") is not equal to ("9")` and missing API assertions.

- [ ] **Step 3: Write minimal implementation in `Sources/iris/GCloudHelper.swift`**

Replace `static let requiredAPIs: [APIInfo]` in `Sources/iris/GCloudHelper.swift` (around lines 21-28) with:

```swift
    /// The nine APIs required by the Google Workspace and Gemini ADC integrations.
    /// (userinfo.email is an OIDC scope — no People API enablement needed.)
    static let requiredAPIs: [APIInfo] = [
        APIInfo(id: "calendar-json.googleapis.com",      displayName: "Google Calendar",    scope: "https://www.googleapis.com/auth/calendar", enabled: false),
        APIInfo(id: "drive.googleapis.com",              displayName: "Google Drive",       scope: "https://www.googleapis.com/auth/drive", enabled: false),
        APIInfo(id: "docs.googleapis.com",               displayName: "Google Docs",        scope: "https://www.googleapis.com/auth/documents", enabled: false),
        APIInfo(id: "sheets.googleapis.com",             displayName: "Google Sheets",      scope: "https://www.googleapis.com/auth/spreadsheets", enabled: false),
        APIInfo(id: "gmail.googleapis.com",              displayName: "Gmail",              scope: "https://www.googleapis.com/auth/gmail.modify", enabled: false),
        APIInfo(id: "tasks.googleapis.com",              displayName: "Google Tasks",       scope: "https://www.googleapis.com/auth/tasks", enabled: false),
        APIInfo(id: "aiplatform.googleapis.com",         displayName: "Vertex AI",          scope: "https://www.googleapis.com/auth/cloud-platform", enabled: false),
        APIInfo(id: "cloudaicompanion.googleapis.com",   displayName: "Cloud AI Companion", scope: "https://www.googleapis.com/auth/cloud-platform", enabled: false),
        APIInfo(id: "generativelanguage.googleapis.com", displayName: "Gemini API",         scope: "https://www.googleapis.com/auth/generative-language", enabled: false),
    ]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GCloudHelperTests`  
Expected: PASS (`Executed 15 tests, with 0 failures`).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/GCloudHelper.swift Tests/irisTests/GCloudHelperTests.swift
git commit -m "feat(gcloud): add Vertex AI, Cloud AI Companion, and Gemini API to GCloudHelper.requiredAPIs

Co-authored-by: Gemini <gemini-cli@google.com>"
```

---

### Task 2: Implement Global Vertex AI ADC Endpoint Toggle in `LLMClient.swift`

**Files:**
- Modify: `Sources/iris/LLMClient.swift:16-80`
- Create: `Tests/irisTests/LLMClientTests.swift`

**Interfaces:**
- Consumes: `ADCCredentialManager.shared.getQuotaProject()`
- Produces: `LLMClient.resolveGeminiRequestURL(modelName:isADC:customBaseURL:quotaProject:) throws -> URL` helper and updated `endpoint(for tier:)` and `generateContent(request:tier:)` that automatically route to `https://aiplatform.googleapis.com/v1/projects/<project>/locations/global/publishers/google/models/<model>:generateContent` when ADC auth mode is selected.

- [ ] **Step 1: Write the failing test in `Tests/irisTests/LLMClientTests.swift`**

Create `Tests/irisTests/LLMClientTests.swift` with the following content:

```swift
import XCTest
@testable import iris

final class LLMClientTests: XCTestCase {
    
    func testResolveGeminiRequestURLAPIKeyModeDefault() throws {
        let url = try LLMClient.resolveGeminiRequestURL(
            modelName: "gemini-3.5-flash",
            isADC: false,
            customBaseURL: "",
            quotaProject: nil
        )
        XCTAssertEqual(url.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent")
    }
    
    func testResolveGeminiRequestURLADCModeDefaultToGlobalVertex() throws {
        let url = try LLMClient.resolveGeminiRequestURL(
            modelName: "gemini-3.5-flash",
            isADC: true,
            customBaseURL: "",
            quotaProject: "gke-bnaylor-hosted-master"
        )
        XCTAssertEqual(url.absoluteString, "https://aiplatform.googleapis.com/v1/projects/gke-bnaylor-hosted-master/locations/global/publishers/google/models/gemini-3.5-flash:generateContent")
    }
    
    func testResolveGeminiRequestURLCustomBaseURLOverridesBoth() throws {
        let custom = "https://custom.proxy.dev/gemini/generate"
        let urlApiKey = try LLMClient.resolveGeminiRequestURL(
            modelName: "gemini-3.5-flash",
            isADC: false,
            customBaseURL: custom,
            quotaProject: nil
        )
        let urlADC = try LLMClient.resolveGeminiRequestURL(
            modelName: "gemini-3.5-flash",
            isADC: true,
            customBaseURL: custom,
            quotaProject: "test-project"
        )
        XCTAssertEqual(urlApiKey.absoluteString, custom)
        XCTAssertEqual(urlADC.absoluteString, custom)
    }
    
    func testResolveGeminiRequestURLADCModeWithoutProjectThrows() {
        XCTAssertThrowsError(try LLMClient.resolveGeminiRequestURL(
            modelName: "gemini-3.5-flash",
            isADC: true,
            customBaseURL: "",
            quotaProject: nil
        )) { error in
            guard let apiError = error as? APIError else {
                XCTFail("Expected APIError, got \(error)")
                return
            }
            XCTAssertTrue(apiError.message.contains("GCP Project ID not found"), "Error message should instruct user to set project: \(apiError.message)")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LLMClientTests`  
Expected: FAIL with compilation error `type 'LLMClient' has no member 'resolveGeminiRequestURL'`.

- [ ] **Step 3: Write minimal implementation in `Sources/iris/LLMClient.swift`**

In `Sources/iris/LLMClient.swift`:

1. Add the static helper `resolveGeminiRequestURL(modelName:isADC:customBaseURL:quotaProject:) throws -> URL` inside `struct LLMClient`:

```swift
    static func resolveGeminiRequestURL(
        modelName: String,
        isADC: Bool,
        customBaseURL: String,
        quotaProject: String?
    ) throws -> URL {
        let baseURLString: String
        if !customBaseURL.isEmpty {
            baseURLString = customBaseURL
        } else if isADC {
            guard let project = quotaProject, !project.isEmpty else {
                throw APIError(message: "GCP Project ID not found. Required for Application Default Credentials (ADC) Vertex AI endpoint. Set via 'gcloud config set project <PROJECT_ID>' or export GOOGLE_CLOUD_QUOTA_PROJECT.")
            }
            baseURLString = "https://aiplatform.googleapis.com/v1/projects/\(project)/locations/global/publishers/google/models/\(modelName):generateContent"
        } else {
            baseURLString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent"
        }
        
        guard let url = URL(string: baseURLString) else {
            throw APIError(message: "Invalid Gemini base URL configuration: \(baseURLString)")
        }
        return url
    }
```

2. Update `endpoint(for tier: ModelTier)` in `LLMClient.swift` (around line 17) to use `resolveGeminiRequestURL`:

```swift
    func endpoint(for tier: ModelTier) -> String {
        let config = ConfigManager.shared
        let modelName = config.getModel(for: tier)
        let isADC = config.geminiAuthMode == GeminiAuthMode.adc.rawValue
        // For synchronous display/inspection in endpoint(for:), use quota project from env if available, or fallback to AI studio URL if project is unknown.
        let envProject = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_QUOTA_PROJECT"] ?? ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"]
        if let url = try? LLMClient.resolveGeminiRequestURL(
            modelName: modelName,
            isADC: isADC,
            customBaseURL: config.geminiBaseURL,
            quotaProject: envProject
        ) {
            return url.absoluteString
        }
        return "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent"
    }
```

3. Update `generateContent(request:tier:)` in `LLMClient.swift` around lines 56-69:

Replace:
```swift
                let baseURLString = config.geminiBaseURL.isEmpty ? "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent" : config.geminiBaseURL
                
                guard var urlComponents = URLComponents(string: baseURLString) else {
                    throw APIError(message: "Invalid Gemini base URL configuration: \(baseURLString)")
                }
                
                if !isADC {
                    urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
                }

                guard let requestURL = urlComponents.url else {
                    throw APIError(message: "Failed to construct Gemini request URL.")
                }
                var urlRequest = URLRequest(url: requestURL)
```

With:
```swift
                let quotaProject = isADC ? await ADCCredentialManager.shared.getQuotaProject() : nil
                let requestURL = try LLMClient.resolveGeminiRequestURL(
                    modelName: modelName,
                    isADC: isADC,
                    customBaseURL: config.geminiBaseURL,
                    quotaProject: quotaProject
                )
                
                guard var urlComponents = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
                    throw APIError(message: "Invalid Gemini request URL: \(requestURL.absoluteString)")
                }
                
                if !isADC {
                    urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
                }

                guard let finalURL = urlComponents.url else {
                    throw APIError(message: "Failed to construct Gemini request URL.")
                }
                var urlRequest = URLRequest(url: finalURL)
```

And in lines 73-79 of `generateContent`:

Replace:
```swift
                if isADC {
                    let accessToken = try await ADCCredentialManager.shared.getAccessToken()
                    urlRequest.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    if let quotaProject = await ADCCredentialManager.shared.getQuotaProject() {
                        urlRequest.addValue(quotaProject, forHTTPHeaderField: "x-goog-user-project")
                    }
                }
```

With:
```swift
                if isADC {
                    let accessToken = try await ADCCredentialManager.shared.getAccessToken()
                    urlRequest.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    if let project = quotaProject {
                        urlRequest.addValue(project, forHTTPHeaderField: "x-goog-user-project")
                    }
                }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LLMClientTests`  
Expected: PASS (`Executed 4 tests, with 0 failures`).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/LLMClient.swift Tests/irisTests/LLMClientTests.swift
git commit -m "feat(gemini): automatically toggle to Global Vertex AI endpoint when ADC auth mode is selected

Co-authored-by: Gemini <gemini-cli@google.com>"
```

---

### Task 3: Complete Test Suite Verification

**Files:**
- Test: `Tests/irisTests`

**Interfaces:**
- Consumes: Tasks 1 and 2
- Produces: Verified passing build and test suite across the entire project.

- [ ] **Step 1: Run complete test suite**

Run: `swift test`  
Expected: All test suites pass with 0 regressions.

- [ ] **Step 2: Commit any cleanups if needed**

```bash
git status
```
(Should be clean.)
