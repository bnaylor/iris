# Automatic Vertex AI ADC Toggle & Expanded Settings GCP APIs Design

**Date:** 2026-08-04  
**Author:** Brian Naylor & Gemini  
**Status:** Approved  

---

## 1. Overview & Motivation
When users select **Application Default Credentials (ADC)** as their Gemini authentication method in Iris, out-of-the-box requests fail with `HTTP 403: ACCESS_TOKEN_SCOPE_INSUFFICIENT` if they hit Google AI Studio (`generativelanguage.googleapis.com`) with a `cloud-platform` OAuth token.

Additionally, while Iris provides an automated GCP/Google Workspace API enablement checklist in its Settings pane, that checklist currently only includes the six Google Workspace APIs (`calendar`, `drive`, `docs`, `sheets`, `gmail`, `tasks`). It lacks the Google Cloud AI APIs needed for ADC and Gemini workflows (`aiplatform.googleapis.com`, `cloudaicompanion.googleapis.com`, and `generativelanguage.googleapis.com`).

This design implements:
1. **Automatic Vertex AI Endpoint Toggle**: Automatically routing Gemini requests to regional Vertex AI endpoints (`https://us-central1-aiplatform.googleapis.com/...`) when ADC auth mode is selected and `geminiBaseURL` is not overridden.
2. **Automatic Model Mapping for Vertex GA**: Mapping AI Studio experimental/default `3.x` model names to Vertex AI `2.x` GA equivalents so default model configurations succeed without `404 Not Found` errors.
3. **Expanded Settings API Enablement Pane**: Adding `aiplatform.googleapis.com`, `cloudaicompanion.googleapis.com`, and `generativelanguage.googleapis.com` to `GCloudHelper.requiredAPIs` so users can inspect and enable them directly from Settings.

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
    * Map the configured model string using a helper `resolveGeminiModelForVertex(_ modelName: String) -> String`:
      * `gemini-3.5-flash` → `gemini-2.5-flash`
      * `gemini-3.1-pro-preview` → `gemini-2.5-pro`
      * `gemini-3.1-flash-lite` → `gemini-2.5-flash`
      * Any other model string is returned unchanged.
    * Construct the regional Vertex AI request URL:
      ```
      https://us-central1-aiplatform.googleapis.com/v1/projects/\(project)/locations/us-central1/publishers/google/models/\(mappedModel):generateContent
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
   * Target URL: `us-central1-aiplatform.googleapis.com/v1/...`.

---

## 4. Verification & Testing Strategy

### 4.1 Unit Tests (`Tests/irisTests/GCloudHelperTests.swift`)
* Update `testRequiredAPIsCount` to assert count `9`.
* Update `testRequiredAPIIDsAreCorrect` to assert presence of `aiplatform.googleapis.com`, `cloudaicompanion.googleapis.com`, and `generativelanguage.googleapis.com`.
* Update `testRequiredAPIScopesAreCorrect` and `testRequiredAPIDisplayNames` to assert the new scopes and display names.

### 4.2 Unit Tests (`Tests/irisTests/LLMClientTests.swift`)
* Add unit test verifying `resolveGeminiModelForVertex(_:)` maps `gemini-3.5-flash` → `gemini-2.5-flash`, `gemini-3.1-pro-preview` → `gemini-2.5-pro`, `gemini-3.1-flash-lite` → `gemini-2.5-flash`, and leaves other models untouched.
* Add unit test verifying endpoint URL construction for both ADC mode (Vertex AI regional URL with project ID) and API key mode (AI Studio URL).

### 4.3 Automated Verification
* Run `swift test` across the repo to verify 0 regressions.
