---
type: spec
title: Anthropic and OpenAI Provider Client Testing Specification
description: Design specification for implementing unit tests for Anthropic and OpenAI API client integrations.
tags: [testing, anthropic, openai, architecture, swift]
timestamp: 2026-07-13T16:30:00Z
---

# Anthropic and OpenAI Provider Client Testing Specification

## 1. Objective
Currently, `AnthropicClient` and `OpenAIClient` are key components for routing LLM requests when the user switches their provider from Gemini. To guarantee stability and prevent regressions, we need a robust unit test suite that verifies request translation, response parsing, and error handling for both clients. 

These tests must run locally and autonomously without requiring actual API keys or making external network requests.

## 2. Approach: Intercepting Network Traffic via `URLProtocol`
Since `AnthropicClient` and `OpenAIClient` make requests using the default network session (`URLSession.shared`), we can use Swift's native `URLProtocol` capabilities to intercept network calls globally during test execution. This allows us to:
1. Capture the exact HTTP request (method, headers, request body JSON) sent by each client.
2. Stub mock responses (JSON bodies, status codes, and HTTP headers) representing successful completions, tool calls, and API errors.
3. Eliminate external network dependencies.

### MockURLProtocol Architecture
We will implement a simple `MockURLProtocol` class within our test target:
```swift
class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
```

In the test suite setup, we will register `MockURLProtocol`:
```swift
override func setUp() {
    super.setUp()
    URLProtocol.registerClass(MockURLProtocol.self)
}

override func tearDown() {
    URLProtocol.unregisterClass(MockURLProtocol.self)
    MockURLProtocol.handler = nil
    super.tearDown()
}
```

## 3. Test Cases to Implement

### A. `AnthropicClientTests`
1. **Request Translation (Text Completion)**:
   - Input: `GeminiRequest` with a text prompt and standard system instructions.
   - Assert: HTTP POST request sent to `https://api.anthropic.com/v1/messages`. Check headers (`x-api-key`, `anthropic-version`, `Content-Type`) and request body mapping (proper `system` field, `messages` roles).
2. **Request Translation (Tools/Function Declarations)**:
   - Input: `GeminiRequest` with function declarations.
   - Assert: Check that Anthropic-style tools (`input_schema`, `name`, `description`) are formatted correctly in the request payload.
3. **Response Parsing (Text Completion)**:
   - Mock Response: Anthropic JSON with text content.
   - Assert: Correctly mapped `GeminiResponse` with candidate containing the text part.
4. **Response Parsing (Tool Call)**:
   - Mock Response: Anthropic JSON containing a `tool_use` part.
   - Assert: Correctly mapped `GeminiResponse` with a candidate containing a `FunctionCall` part.
5. **Error Handling**:
   - Mock Response: Non-200 HTTP response.
   - Assert: Throw an `APIError` with the status code and raw response message.

### B. `OpenAIClientTests`
1. **Request Translation (Text Completion)**:
   - Input: `GeminiRequest` with user prompt and system instruction.
   - Assert: HTTP POST to `https://api.openai.com/v1/chat/completions`, headers (`Authorization`, `Content-Type`), and body (proper `system` role role mapping, messages structure).
2. **Request Translation (Tools/Function Declarations)**:
   - Input: `GeminiRequest` containing tools.
   - Assert: Schema is converted to OpenAI-style tools configuration.
3. **Response Parsing (Text Completion)**:
   - Mock Response: OpenAI completion payload.
   - Assert: Correct translation to `GeminiResponse`.
4. **Response Parsing (Tool/Function Call)**:
   - Mock Response: OpenAI completion payload with `tool_calls`.
   - Assert: Correct translation to `GeminiResponse` containing a `FunctionCall` part.
5. **Error Handling**:
   - Mock Response: HTTP 400 or 500 error status.
   - Assert: Throw a clear `APIError`.

## 4. Risks & Mitigations
- **Global Interception Conflict**: Since `URLSession.shared` is modified globally by `URLProtocol`, we must ensure tests do not run in parallel threads where they might overwrite `MockURLProtocol.handler`. We will isolate test state by setting/clearing the handler before and after each test case.
- **Strict Parsing/Key Discrepancies**: If any dictionary casting or formatting fails, the tests will fail immediately, providing invaluable alerts about format mismatches.
