# Google Workspace OAuth Setup

This guide walks you through obtaining a Client ID and Client Secret so Iris can connect to Google Workspace (Calendar, Drive, Docs, Sheets, Gmail, Tasks).

## Option 1: gcloud CLI (Recommended)

If you have `gcloud` installed, Iris auto-detects it and shows your authenticated account and project in the Setup Guide.

### Step 1: Install & authenticate gcloud

```bash
# Install (macOS)
brew install google-cloud-sdk

# Login
gcloud auth login

# Set your project (create one if needed)
gcloud projects list
gcloud config set project YOUR_PROJECT_ID
```

### Step 2: Enable required APIs

In the Iris Integrations tab, expand the **Setup Guide**. Under "Option 1: gcloud CLI", you'll see a checklist of seven APIs. Tap **Enable** next to each one, or run them manually:

```bash
gcloud services enable calendar-json.googleapis.com --quiet
gcloud services enable people.googleapis.com --quiet
gcloud services enable drive.googleapis.com --quiet
gcloud services enable docs.googleapis.com --quiet
gcloud services enable sheets.googleapis.com --quiet
gcloud services enable gmail.googleapis.com --quiet
gcloud services enable tasks.googleapis.com --quiet
```

Tap **Refresh API status** to confirm all seven show green checkmarks.

### Step 3: Create an OAuth 2.0 Client ID

Tap **Open Credentials Page** in the Setup Guide (this opens `console.cloud.google.com/apis/credentials?project=YOUR_PROJECT`).

1. Click **Create Credentials** → **OAuth client ID**
2. Application type: **Desktop app**
3. Give it a name (e.g. "Iris Desktop")
4. Click **Create**
5. Copy the **Client ID** and **Client Secret**

### Step 4: Paste into Iris

Paste the Client ID and Client Secret into the fields in the Integrations tab, then tap **Connect to Google**.

---

## Option 2: Google Cloud Console (Manual)

### Step 1: Open the Google Cloud Console

Go to [console.cloud.google.com](https://console.cloud.google.com) and select or create a project.

### Step 2: Enable the required APIs

Navigate to **APIs & Services** → **Enabled APIs & Services** → **+ Enable APIs and Services**.

Search for and enable each of these:

| API | Service Name |
|---|---|
| Google Calendar API | `calendar-json.googleapis.com` |
| Google People API | `people.googleapis.com` |
| Google Drive API | `drive.googleapis.com` |
| Google Docs API | `docs.googleapis.com` |
| Google Sheets API | `sheets.googleapis.com` |
| Gmail API | `gmail.googleapis.com` |
| Google Tasks API | `tasks.googleapis.com` |

### Step 3: Create OAuth 2.0 credentials

1. Go to **APIs & Services** → **Credentials**
2. Click **Create Credentials** → **OAuth client ID**
3. Select **Desktop app** as the application type
4. Name it (e.g. "Iris Desktop")
5. Click **Create**
6. Copy the **Client ID** and **Client Secret**

### Step 4: Configure in Iris

Paste the credentials into Iris's **Settings → Integrations** tab, then tap **Connect to Google**.

---

## OAuth Scopes Used

Iris requests the following scopes during the OAuth consent flow:

| Scope | Purpose |
|---|---|
| `https://www.googleapis.com/auth/calendar` | Read/write calendar events |
| `https://www.googleapis.com/auth/userinfo.email` | Verify authenticated user email |
| `https://www.googleapis.com/auth/drive` | Search and read files in Drive |
| `https://www.googleapis.com/auth/documents` | Read Google Docs content |
| `https://www.googleapis.com/auth/spreadsheets` | Read Google Sheets data |
| `https://www.googleapis.com/auth/gmail.modify` | List and send emails |
| `https://www.googleapis.com/auth/tasks` | Read/write Google Tasks |

## Troubleshooting

- **"Client ID and Secret required"**: Ensure both fields are filled in before tapping Connect.
- **"Token exchange failed"**: Verify the Client Secret is correct and matches the Client ID from the same OAuth client.
- **OAuth consent screen shows an error**: Ensure the OAuth client is in a project where the consent screen is configured (APIs & Services → OAuth consent screen → External → Publishing status: Testing is fine for personal use).
- **Redirect URI mismatch**: Iris uses `http://localhost` as the redirect URI. Make sure this is added as an authorized redirect URI when creating the OAuth client (Desktop app type should include this by default).
