# Global Hotkeys

Iris runs in the background of macOS as a persistent native application, allowing you to invoke it instantly over any other application. 

By default, the shortcut to toggle the main Iris Chat window is **`Cmd + Shift + Space`**.

## How It Works
*   **Active Overlays:** When you press the hotkey, Iris evaluates if the chat window is currently visible and active.
*   **Show:** If Iris is hidden or behind other applications, the hotkey brings the window to the front and focuses the text input field, making it ready for immediate use.
*   **Hide:** If Iris is already the foreground application, the hotkey seamlessly orders the window out (hides it), returning focus to whatever you were previously working on.

## Customization
You can easily customize the hotkey at any time:
1.  Open the **Settings Window** (`Cmd + ,` or via the Menu Bar).
2.  Locate the **Global Shortcuts** section at the top of the pane.
3.  Click the recorder next to **Toggle Iris**.
4.  Press your desired key combination.

The new shortcut will be applied instantly and bound via macOS's native `KeyboardShortcuts` implementation, requiring no system restarts.
