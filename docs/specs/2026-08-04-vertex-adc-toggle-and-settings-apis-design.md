# Automatic Vertex AI ADC Toggle & Expanded Settings GCP APIs Design

**Date:** 2026-08-04  
**Author:** Brian Naylor & Gemini  
**Status:** Approved  

---

## 1. Overview & Motivation
When users select **Application Default Credentials (ADC)** as their Gemini authentication method in Iris, out-of-the-box requests fail with `HTTP 403: ACCESS_TOKEN_SCOPE_INSUFFICIENT` if they hit Google AI Studio (`generativelanguage.googleapis.com`) with a `cloud-platform` OAuth token.

Additionally, while Iris provides an automated GCP/Google Workspace API enablement checklist in its Settings pane, that checklist currently only includes the six Google Workspace APIs (`calendar`, `drive`, `docs`, `sheets`, `gmail`, `tasks`). It lacks the Google Cloud AI APIs needed for ADC and Gemini workflows (`aiplatform.googleapis.com`, `cloudaicompanion.googleapis.com`, and `generativelanguage.googleapis.com`).

This design implements:
1. **Automatic Vertex AI Global Endpoint Toggle**: Automatically routing Gemini requests to the Global Vertex AI endpoint (`https://aiplatform.googleapis.com/.../locations/global/...`) when ADC auth mode is selected and `geminiBaseURL` is not overridden. Because Gemini 3.x models (`gemini-3.5-flash`, `gemini-3.1-pro-preview`, etc.) are deployed on Global and Multi-Region shards, targeting `locations/global` allows modern Gemini 3.x models to work natively out of the box without any model down-mapping.
2. **Expanded Settings API Enablement Pane**: Adding `aiplatform.googleapis.com`, `cloudaicompanion.googleapis.com`, and `generativelanguage.googleapis.com` to `GCloudHelper.requiredAPIs` so users can inspect and enable them directly from Settings.

---

## 2. Architecture & Components

### 2.1 LLMClient (`Sources/iris/LLMClient.swift`)
* **Endpoint Construction**:
  * In `generateContent(request:tier:)` and `endpoint(for tier:)`, check if an explicit `config.geminiBaseURL` is configured. If non-empty, honor the custom URL verbatim.
  * When `config.geminiBaseURL.isEmpty == true` and `config.geminiAuthMode == GeminiAuthMode.adc.rawValue`:
    * Fetch the quota project ID via `await ADCCredentialManager.shared.getQuotaProject()`.
    * If `project` is `nil`, throw an explicit `APIError`:
      ```
      GCP Project ID not found. Required for Application Default Credentials (ADC) Vertex AI endpoint. Set via 'gcloud config set project <PROJECT_ID>' or export GOOGLE_CLOUD_QUOTA_PROJECT.
      ```
    * Construct the Global Vertex AI request URL:
      ```
      https://aiplatform.googleapis.com/v1/projects/\(project)/locations/global/publishers/google/models/\(modelName):generateContent
      ```
  * When `config.geminiAuthMode != GeminiAuthMode.adc.rawValue`, default to the AI Studio endpoint:
    ```
    https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent
    ```

### 2.2 GCloudHelper (`Sources/iris/GCloudHelper.swift`)
* **Expanded `requiredAPIs` Array**:
  Add three new `APIInfo` entries to `GCloudHelper.requiredAPIs`:
  ```swift
  APIInfo(id: "aiplatform.googleapis.com",         displayName: "Vertex AI",          scope: "https://www.googleapis.com/auth/cloud-platform", enabled: false),
  APIInfo(id: "cloudaicompanion.googleapis.com",   displayName: "Cloud AI Companion", scope: "https://www.googleapis.com/auth/cloud-platform", enabled: false),
  APIInfo(id: "generativelanguage.googleapis.com", displayName: "Gemini API",         scope: "https://www.googleapis.com/auth/generative-language", enabled: false),
  ```
* **Settings UI Integration**:
  No changes are required in `SettingsView.swift` layout code because it binds directly to `GCloudHelper.requiredAPIs`. The API checklist will render 9 APIs instead of 6, supporting live status probes and one-click `gcloud services enable <id>` execution.

---

## 3. Data Flow & Security
1. When `generateContent` runs under ADC mode:
   * `ADCCredentialManager.shared.getAccessToken()` retrieves the ADC OAuth access token.
   * `ADCCredentialManager.shared.getQuotaProject()` resolves the active GCP project ID from `~/.config/gcloud/application_default_credentials.json`, `GOOGLE_CLOUD_QUOTA_PROJECT`, or `gcloud config get-value project`.
   * Headers injected:
     * `Authorization: Bearer <accessToken>`
     * `x-goog-user-project: <quotaProject>`
   * Target URL: `https://aiplatform.googleapis.com/v1/projects/\(quotaProject)/locations/global/publishers/google/models/\(modelName):generateContent`.

---

## 4. Verification & Testing Strategy

### 4.1 Unit Tests (`Tests/irisTests/GCloudHelperTests.swift`)
* Update `testRequiredAPIsCount` to assert count `9`.
* Update `testRequiredAPIIDsAreCorrect` to assert presence of `aiplatform.googleapis.com`, `cloudaicompanion.googleapis.com`, and `generativelanguage.googleapis.com`.
* Update `testRequiredAPIScopesAreCorrect` and `testRequiredAPIDisplayNames` to assert the new scopes and display names.

### 4.2 Unit Tests (`Tests/irisTests/LLMClientTests.swift`)
* Add unit test verifying endpoint URL construction for ADC mode targets `https://aiplatform.googleapis.com/v1/projects/<project>/locations/global/publishers/google/models/<model>:generateContent`.
* Add unit test verifying endpoint URL construction for API key mode targets AI Studio URL.

### 4.3 Automated Verification
* Run `swift test` across the repo to verify 0 regressions.
