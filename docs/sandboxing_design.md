# Subagent Sandboxing Design

## Motivation

As Iris runs on the user's local machine, it possesses the capability to execute terminal commands via the `run_command` primitive. While the system utilizes security heuristics and a user-approval prompt for dangerous commands, allowing an autonomous agent (or "subagent") to scrape the web, execute untrusted downloaded scripts, or run multi-step code compilation loops poses a security risk to the host macOS environment.

To mitigate this, Iris features an **opt-in subagent sandboxing system** using [apple/container](https://github.com/apple/container).

## Core Technologies

*   **`apple/container`:** A Swift-native CLI tool that runs OCI-compatible container images as lightweight Linux virtual machines on Apple Silicon. It provides an API functionally similar to Docker, but deeply optimized for macOS's native Virtualization.framework.
*   **Opt-In UX:** Because `apple/container` requires a system-level installation (and administrator privileges to install the signed `pkg`), it is an optional capability rather than a hard dependency. 

## Architecture & Data Flow

### 1. Opt-In & Automatic Installation
In the `SettingsView`, users can toggle **"Enable sandboxing for subagents"**. 

When toggled:
1. `SandboxingManager.swift` probes the system for `/usr/local/bin/container`.
2. If missing, it transparently downloads the latest signed `pkg` release from GitHub into `/tmp`.
3. It spawns an `NSAppleScript` payload requesting administrator privileges to run `installer -pkg` and initialize the background daemon (`container system start`).
4. Once successfully installed, the config state updates and the `sandboxImage` (defaulting to `ubuntu:latest`) becomes configurable.

### 2. Transparent Execution
Iris intercepts the `run_command` tool execution inside `ToolExecutor.swift`.

When sandboxing is enabled:
*   Instead of spawning `/bin/zsh -c "<command>"`, Iris spawns `/usr/local/bin/container`.
*   The command is wrapped as: `container run --rm <sandboxImage> bash -c "<command>"`.
*   **Workspace Binding:** To ensure the agent can still accomplish tasks on the host filesystem (like editing local project files), the container bind-mounts the active workspace directly into the VM:
    `-v /host/path:/host/path --workdir /host/path`

This transparent pass-through allows the agent to write files, run linters, and browse directories seamlessly without realizing it is executing within a Linux VM, while simultaneously preventing the agent from escaping into the user's root directories or accessing sensitive macOS host resources outside the designated workspace.

## Future Considerations
*   **Subagent Constraints:** As the subagent architecture evolves, we may restrict certain subagents (e.g., a pure "Researcher" agent) from receiving volume mounts altogether, isolating them entirely from the host filesystem.
*   **Network Constraints:** Future updates could pass flags to `apple/container` to limit outbound network access for agents that should solely be operating on local files.
