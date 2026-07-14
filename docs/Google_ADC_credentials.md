# Google Application Default Credentials (ADC) Setup for Iris

This guide details how to configure and use **Application Default Credentials (ADC)** with Google's Gemini models in Iris.

---

## Overview

Iris supports both standard Gemini API Keys and Google Cloud **Application Default Credentials (ADC)**. ADC allows you to authenticate using your local `gcloud` developer identity or GCP service account credentials without hardcoding API keys.

Because Iris calls Google's REST APIs directly via native HTTP requests, specific OAuth scopes and quota project headers are required.

---

## Step-by-Step Setup

### 1. Enable Required APIs in Google Cloud (Pantheon)

Before authenticating locally, ensure the necessary APIs are enabled in your GCP project:

* **Generative Language API** (`generativelanguage.googleapis.com`) — required for Google AI Studio / Developer Gemini API endpoints.
* **Vertex AI API** (`aiplatform.googleapis.com`) — required if using GCP Vertex AI endpoints.

You can enable these via the Google Cloud Console (Pantheon) API Library or via the `gcloud` CLI:

```bash
# Enable Generative Language API
gcloud services enable generativelanguage.googleapis.com

# (Optional) Enable Vertex AI API
gcloud services enable aiplatform.googleapis.com
```

---

### 2. Authenticate ADC with Required Scopes

Run the following command in your terminal. **Crucially, you must include both the `cloud-platform` and `generative-language` scopes**:

```bash
gcloud auth application-default login --scopes="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/generative-language"
```

> ⚠️ **Important**: Standard `gcloud auth application-default login` without `--scopes` only requests default GCP scopes, which causes `HTTP 403: ACCESS_TOKEN_SCOPE_INSUFFICIENT` errors when calling `generativelanguage.googleapis.com`.

---

### 3. Configure Your Quota & Billing Project

Google Cloud APIs require a **Quota Project** to track usage and billing when authenticating with OAuth/ADC access tokens.

Set your default project using any of the following methods (ordered by precedence):

1. **Environment Variable**:
   ```bash
   export GOOGLE_CLOUD_QUOTA_PROJECT="your-gcp-project-id"
   # or
   export GOOGLE_CLOUD_PROJECT="your-gcp-project-id"
   ```

2. **ADC Credentials JSON (`quota_project_id`)**:
   `gcloud auth application-default login` will automatically write your active gcloud project to `~/.config/gcloud/application_default_credentials.json` as `"quota_project_id"`.

3. **`gcloud` CLI Config**:
   ```bash
   gcloud config set project your-gcp-project-id
   ```

---

### 4. Enable ADC in Iris Settings

1. Open **Iris Settings**.
2. Set **Primary Provider** to `Gemini`.
3. Under **Authentication Method**, select `Application Default Credentials (ADC)`.
4. Leave **Gemini Base URL** blank for default endpoint (`https://generativelanguage.googleapis.com/v1beta/models/...`) or set your custom base URL.

---

## Architecture & Implementation Details

Iris handles ADC internally via `ADCCredentialManager.swift` and `LLMClient.swift`:

1. **Token Refresh & Caching**:
   - Iris checks `~/.config/gcloud/application_default_credentials.json` (or `$GOOGLE_APPLICATION_CREDENTIALS`) and exchanges the refresh token directly at `oauth2.googleapis.com/token`.
   - If the file is absent, Iris invokes `gcloud auth application-default print-access-token`.
   - Access tokens are cached in memory and refreshed automatically prior to expiration.

2. **Quota Project Header Forwarding**:
   - When ADC mode is active, Iris automatically resolves the active project ID and attaches the mandatory `x-goog-user-project: <quota_project_id>` HTTP header on all REST calls.

---

## Troubleshooting

| Error | Cause | Solution |
| :--- | :--- | :--- |
| `HTTP 401: ACCESS_TOKEN_TYPE_UNSUPPORTED` | `gcloud auth` user token used instead of ADC token | Run `gcloud auth application-default login` (do not rely on standard `gcloud auth login`). |
| `HTTP 403: ACCESS_TOKEN_SCOPE_INSUFFICIENT` | ADC credentials missing the `generative-language` scope | Re-authenticate using: `gcloud auth application-default login --scopes="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/generative-language"` |
| `HTTP 403: Quota project missing / PERMISSION_DENIED` | No GCP project associated with ADC request | Set project via `gcloud config set project <PROJECT_ID>` or export `GOOGLE_CLOUD_QUOTA_PROJECT=<PROJECT_ID>`. |
