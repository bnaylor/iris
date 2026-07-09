# Google Workspace OAuth Integration

Iris supports natively connecting to Google Workspace APIs (like Calendar, Docs, Drive, and Sheets) to empower the underlying AI agent with external memory and scheduling capabilities. 

Because Iris is a native macOS app, it handles the OAuth 2.0 loopback flow without requiring any backend servers.

## How It Works
1.  **Native TCP Listener**: When you initiate a connection, Iris starts a lightweight, temporary TCP server on a random open port using Apple's `Network` framework.
2.  **Consent Screen**: Iris opens your default web browser and sends you to the Google Accounts consent screen.
3.  **Local Redirection**: Once you grant access, Google redirects you to `http://localhost:<port>/callback`.
4.  **Token Exchange**: Iris intercepts the HTTP request, grabs the authorization code, and immediately trades it for an **Access Token** and **Refresh Token** via the Google OAuth API. 

## Setup Instructions
To enable this feature:
1.  Navigate to the [Google Cloud Console](https://console.cloud.google.com/).
2.  Create a new project or select an existing one.
3.  Navigate to **APIs & Services** > **Credentials**.
4.  Click **Create Credentials** > **OAuth client ID**.
5.  Select **Desktop app** (or Web application with `http://localhost` as an authorized redirect URI).
6.  Copy the generated **Client ID** and **Client Secret**.
7.  Open the Iris Settings window (`Cmd + ,` or via the Menu Bar).
8.  Paste the credentials into the **Google Workspace (OAuth)** section.
9.  Click **Connect to Google** and approve the required permissions in your browser.

## Security
Tokens are persisted safely by Iris via `ConfigManager` natively into macOS's `UserDefaults` (and can be upgraded to the Keychain in future iterations). The local web server shuts down instantly after the authorization code is received.
