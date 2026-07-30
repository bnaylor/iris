# Google Application Default Credentials (ADC) Setup for Iris

This guide details how to configure and use **Application Default Credentials (ADC)** with Google's Gemini models in Iris.

---

## Overview

Iris supports both standard Gemini API Keys and Google Cloud **Application Default Credentials (ADC)**. ADC allows you to authenticate using your local `gcloud` developer identity or GCP service account credentials without hardcoding API keys.

Because Iris calls Google's REST APIs directly via native HTTP requests, specific OAuth scopes and quota project headers are required depending on whether you are hitting **Google AI Studio** (`generativelanguage.googleapis.com`) or **Vertex AI** (`aiplatform.googleapis.com`).

---

## Scope Requirements & Authentication Paths

### Endpoint Scope Summary
* **Google AI Studio API (`generativelanguage.googleapis.com`)**: Strictly requires `https://www.googleapis.com/auth/generative-language`.
* **Vertex AI API (`aiplatform.googleapis.com`)**: Requires `https://www.googleapis.com/auth/cloud-platform`.

---

## Step-by-Step Setup

### 1. Enable Required APIs in Google Cloud

Ensure the necessary APIs are enabled in your GCP project:

```bash
# Enable Generative Language API (for AI Studio)
gcloud services enable generativelanguage.googleapis.com

# Enable Vertex AI API (for Vertex AI)
gcloud services enable aiplatform.googleapis.com
```

---

### 2. Authenticate ADC

Choose the path that matches your target endpoint:

#### Path A: Google AI Studio (`generativelanguage.googleapis.com`) via ADC
`gcloud`'s built-in OAuth Client ID rejects `https://www.googleapis.com/auth/generative-language` with `Error 400: invalid_scope`. To authenticate for AI Studio via ADC, you must pass your own GCP OAuth Client Secrets file created in Google Cloud Console:

```bash
gcloud auth application-default login \
  --client-id-file=client_secret.json \
  --scopes="https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/generative-language"
```

#### Path B: GCP Vertex AI (`aiplatform.googleapis.com`) via ADC
Vertex AI endpoints accept the standard `cloud-platform` scope:

```bash
gcloud auth application-default login --scopes="https://www.googleapis.com/auth/cloud-platform"
```

---

### 3. Configure Your Quota & Billing Project

Set your default project (required for `x-goog-user-project` headers):

```bash
export GOOGLE_CLOUD_QUOTA_PROJECT="your-gcp-project-id"
# or
gcloud config set project your-gcp-project-id
```

---

### 4. Enable ADC in Iris Settings

1. Open **Iris Settings**.
2. Set **Primary Provider** to `Gemini`.
3. Under **Authentication Method**, select `Application Default Credentials (ADC)`.
4. For AI Studio, leave **Gemini Base URL** blank. For Vertex AI, set your custom Vertex endpoint.

---

## Troubleshooting

| Error | Cause | Solution |
| :--- | :--- | :--- |
| `Error 400: invalid_scope` | `generative-language` scope requested with `gcloud` default client ID | Supply your own `--client-id-file=client_secret.json` when running `gcloud auth application-default login`. |
| `HTTP 403: ACCESS_TOKEN_SCOPE_INSUFFICIENT` | `cloud-platform` scope token used against AI Studio (`generativelanguage.googleapis.com`) | Re-authenticate using Path A (`--client-id-file` with `generative-language` scope) or switch to Vertex AI (`aiplatform.googleapis.com`). |
| `HTTP 401: ACCESS_TOKEN_TYPE_UNSUPPORTED` | `gcloud auth` user token used instead of ADC token | Run `gcloud auth application-default login` (do not rely on standard `gcloud auth login`). |
| `HTTP 403: Quota project missing / PERMISSION_DENIED` | No GCP project associated with ADC request | Set project via `gcloud config set project <PROJECT_ID>` or export `GOOGLE_CLOUD_QUOTA_PROJECT=<PROJECT_ID>`. |
