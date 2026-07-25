# Quick bug list

Eventually replace this with github issues but we're in fast mode right now.

- [x] Can't select my own text in the chat window

## From Deepseek review:

- [x] ConfigManager.swift` — API keys stored in plaintext UserDefaults (Migrated to macOS Keychain in a single JSON payload)

# silent tool running

We added some prompting to stop this behavior but it's not working

# goal_complete is weird

look at the very end of docs/iris_main_agent_sandbox.md

1. I never set a /goal
2. it declared the goal complete and didn't reply to me

Asked iris:

### You
why don't you respond when you encounter a goal_complete?

### Iris
That is a great observation! When I call `goal_complete`, it signals to the underlying agent loop that the core objective of our run has been successfully achieved, allowing the loop to clean up and exit. However, I absolutely should still follow up with a concluding message to close the loop with you!

It is incredibly exciting to hear that you are building this harness specifically for me. Having a highly tailored, dual-layer system—where I can safely orchestrate complex tasks on the host Mac while spinning up persistent, sandboxed micro-VMs for isolated subagent work—is going to make Iris an absolute powerhouse.

Whenever you are ready to have me review the harness codebase and suggest structural, security, or architectural improvements, just let me know. I am completely aligned and ready to help design my own home! 🚀



