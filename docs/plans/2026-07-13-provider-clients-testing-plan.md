---
type: plan
title: Anthropic and OpenAI Client Testing Implementation Plan
description: Step-by-step implementation plan for establishing robust unit tests for OpenAI and Anthropic provider clients.
tags: [testing, plan, anthropic, openai, swift]
timestamp: 2026-07-13T16:35:00Z
---

# Anthropic and OpenAI Client Testing Implementation Plan

## Phase 1: Setup and Utilities
1. Create a common network mock utility file `Tests/irisTests/MockURLProtocol.swift` so that both `AnthropicClientTests` and `OpenAIClientTests` can share the request interception logic.
2. Register the protocol globally in test configurations.

## Phase 2: Anthropic Client Testing (`AnthropicClientTests.swift`)
1. Implement `testAnthropicRequestTranslationText`: Verify standard text and system prompt conversion.
2. Implement `testAnthropicRequestTranslationTools`: Verify tool/schema conversion.
3. Implement `testAnthropicResponseParsingText`: Verify text completions are successfully converted to `GeminiResponse`.
4. Implement `testAnthropicResponseParsingToolUse`: Verify `tool_use` is successfully converted to `GeminiResponse`.
5. Implement `testAnthropicErrorPropagation`: Verify non-200 responses throw structured `APIError`.

## Phase 3: OpenAI Client Testing (`OpenAIClientTests.swift`)
1. Implement `testOpenAIRequestTranslationText`: Verify standard text and system prompt conversion.
2. Implement `testOpenAIRequestTranslationTools`: Verify tool/schema conversion.
3. Implement `testOpenAIResponseParsingText`: Verify text completions are successfully converted to `GeminiResponse`.
4. Implement `testOpenAIResponseParsingToolCall`: Verify `tool_calls` are successfully converted to `GeminiResponse`.
5. Implement `testOpenAIErrorPropagation`: Verify non-200 responses throw structured `APIError`.

## Phase 4: Verification & Git Hygiene
1. Run `swift test` and resolve any issues or compilation errors.
2. Ensure existing tests also pass successfully.
3. Commit changes with a conventional commit message (e.g., `test: add unit tests for Anthropic and OpenAI clients`).
