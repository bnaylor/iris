# File Attachments & Vision Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement non-text file attachments (images, PDFs, documents, text files) with drag-and-drop, paperclip UI, native macOS document parsing, and capability-aware vision routing (native LLM vision or local auxiliary model fallback).

**Architecture:** Extend Iris data models (`ChatMessage`, `Part`) with `FileAttachment` and `InlineData`. Implement `AttachmentProcessor` to parse documents via `PDFKit`/`NSAttributedString` and `VisionRouter` to route images natively or via `AuxiliaryModelManager`. Build `AttachmentBarView`, drag-and-drop overlays, and `NSOpenPanel` bindings in `ChatView`.

**Tech Stack:** Swift, SwiftUI, AppKit, PDFKit, Foundation, XCTest.

## Global Constraints

- Swift 5.9+ / macOS 14+ baseline.
- Zero extra third-party binary dependencies for file parsing (use native `PDFKit` and `NSAttributedString`).
- Maintain full backwards compatibility for existing saved `ChatMessage` JSON conversations.
- Include co-author attribution for commits: `Co-authored-by: Gemini <gemini-cli@google.com>`.

---

### Task 1: Data Models & Serialization

**Files:**
- Create: `Sources/iris/FileAttachment.swift`
- Modify: `Sources/iris/AppState.swift`
- Modify: `Sources/iris/Models.swift`
- Create: `Tests/irisTests/FileAttachmentSerializationTests.swift`

**Interfaces:**
- Consumes: Existing `ChatMessage` struct in `AppState.swift`.
- Produces: `AttachmentCategory`, `FileAttachment`, `InlineData`, updated `ChatMessage` with `attachments: [FileAttachment]`, updated `Part` with `inlineData: InlineData?`.

- [ ] **Step 1: Write failing serialization tests**

Create `Tests/irisTests/FileAttachmentSerializationTests.swift`:
```swift
import XCTest
@testable import iris

final class FileAttachmentSerializationTests: XCTestCase {
    func testFileAttachmentJSONEncodingAndDecoding() throws {
        let url = URL(fileURLWithPath: "/tmp/sample.png")
        let attachment = FileAttachment(
            id: UUID(),
            filename: "sample.png",
            fileURL: url,
            mimeType: "image/png",
            fileSize: 1024,
            category: .image
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(attachment)
        let decoded = try decoder.decode(FileAttachment.self, from: data)
        
        XCTAssertEqual(decoded.filename, "sample.png")
        XCTAssertEqual(decoded.mimeType, "image/png")
        XCTAssertEqual(decoded.fileSize, 1024)
        XCTAssertEqual(decoded.category, .image)
    }

    func testChatMessageBackwardsCompatibility() throws {
        let jsonWithoutAttachments = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "role": "user",
            "content": "Hello"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let msg = try decoder.decode(ChatMessage.self, from: jsonWithoutAttachments)
        XCTAssertEqual(msg.content, "Hello")
        XCTAssertTrue(msg.attachments.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FileAttachmentSerializationTests`
Expected: FAIL with "cannot find type 'FileAttachment' in scope"

- [ ] **Step 3: Create `FileAttachment.swift` and update `AppState.swift` & `Models.swift`**

Create `Sources/iris/FileAttachment.swift`:
```swift
import Foundation

public enum AttachmentCategory: String, Codable {
    case image
    case pdf
    case document
    case text
    case unknown
}

public struct FileAttachment: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public let filename: String
    public let fileURL: URL
    public let mimeType: String
    public let fileSize: Int64
    public let category: AttachmentCategory

    public init(
        id: UUID = UUID(),
        filename: String,
        fileURL: URL,
        mimeType: String,
        fileSize: Int64,
        category: AttachmentCategory
    ) {
        self.id = id
        self.filename = filename
        self.fileURL = fileURL
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.category = category
    }
}

public struct InlineData: Codable, Equatable {
    public let mimeType: String
    public let data: String // Base64 encoded

    public init(mimeType: String, data: String) {
        self.mimeType = mimeType
        self.data = data
    }
}
```

In `Sources/iris/Models.swift`:
Add `public var inlineData: InlineData? = nil` to `Part`.

In `Sources/iris/AppState.swift`:
Update `ChatMessage`:
```swift
struct ChatMessage: Identifiable, Codable {
    var id = UUID()
    let role: ChatRole
    let content: String
    var attachments: [FileAttachment] = []

    enum CodingKeys: String, CodingKey {
        case id, role, content, attachments
    }

    init(id: UUID = UUID(), role: ChatRole, content: String, attachments: [FileAttachment] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decode(ChatRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        attachments = try container.decodeIfPresent([FileAttachment].self, forKey: .attachments) ?? []
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FileAttachmentSerializationTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/FileAttachment.swift Sources/iris/Models.swift Sources/iris/AppState.swift Tests/irisTests/FileAttachmentSerializationTests.swift
git commit -m "feat: add FileAttachment and InlineData models with ChatMessage backwards compatibility

Co-authored-by: Gemini <gemini-cli@google.com>"
```

---

### Task 2: Provider Multimodal Payload Adapters

**Files:**
- Modify: `Sources/iris/LLMClient.swift`
- Modify: `Sources/iris/OpenAIClient.swift`
- Modify: `Sources/iris/AnthropicClient.swift`
- Modify: `Tests/irisTests/OpenAIClientTests.swift`
- Modify: `Tests/irisTests/AnthropicClientTests.swift`

**Interfaces:**
- Consumes: `Part.inlineData` from Task 1.
- Produces: Correct REST payload formats for Gemini (`inlineData`), OpenAI (`image_url`), and Anthropic (`image` block).

- [ ] **Step 1: Write failing tests for OpenAI & Anthropic image payload serialization**

In `Tests/irisTests/OpenAIClientTests.swift`:
```swift
func testOpenAIInlineDataPayloadFormat() throws {
    let part = Part(text: nil, inlineData: InlineData(mimeType: "image/png", data: "b64data"))
    let content = Content(role: "user", parts: [part])
    let request = GeminiRequest(contents: [content])
    // Verify serialization includes type "image_url"
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter OpenAIClientTests`
Expected: FAIL or missing image_url formatting in payload.

- [ ] **Step 3: Update LLMClient, OpenAIClient, and AnthropicClient**

In `OpenAIClient.swift`: Update message formatting to handle `part.inlineData`:
```swift
if let inline = part.inlineData {
    messageParts.append([
        "type": "image_url",
        "image_url": ["url": "data:\(inline.mimeType);base64,\(inline.data)"]
    ])
}
```

In `AnthropicClient.swift`: Update message formatting to handle `part.inlineData`:
```swift
if let inline = part.inlineData {
    contentBlocks.append([
        "type": "image",
        "source": [
            "type": "base64",
            "media_type": inline.mimeType,
            "data": inline.data
        ]
    ])
}
```

In `LLMClient.swift`: Ensure Gemini REST payload serializes `inlineData` directly.

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter OpenAIClientTests && swift test --filter AnthropicClientTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/LLMClient.swift Sources/iris/OpenAIClient.swift Sources/iris/AnthropicClient.swift Tests/irisTests/OpenAIClientTests.swift Tests/irisTests/AnthropicClientTests.swift
git commit -m "feat: add multimodal inlineData payload support for Gemini, OpenAI, and Anthropic clients

Co-authored-by: Gemini <gemini-cli@google.com>"
```

---

### Task 3: Native Document Text Extraction Engine

**Files:**
- Create: `Sources/iris/AttachmentProcessor.swift`
- Create: `Tests/irisTests/AttachmentProcessorTests.swift`

**Interfaces:**
- Consumes: `FileAttachment` structs.
- Produces: `AttachmentProcessingResult` with extracted document text and native image `Part`s.

- [ ] **Step 1: Write failing tests for AttachmentProcessor**

Create `Tests/irisTests/AttachmentProcessorTests.swift`:
```swift
import XCTest
@testable import iris

final class AttachmentProcessorTests: XCTestCase {
    func testTextFileExtraction() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("sample_\(UUID().uuidString).txt")
        try "Hello World File Attachment".write(to: fileURL, atomically: true, encoding: .utf8)
        
        let attachment = FileAttachment(
            filename: fileURL.lastPathComponent,
            fileURL: fileURL,
            mimeType: "text/plain",
            fileSize: 26,
            category: .text
        )
        
        let result = try await AttachmentProcessor.process(attachments: [attachment], primarySupportsVision: true)
        XCTAssertTrue(result.extractedPromptText.contains("Hello World File Attachment"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AttachmentProcessorTests`
Expected: FAIL with "cannot find 'AttachmentProcessor' in scope"

- [ ] **Step 3: Implement `AttachmentProcessor.swift`**

Create `Sources/iris/AttachmentProcessor.swift`:
```swift
import Foundation
import PDFKit
import AppKit

public struct AttachmentProcessingResult {
    public let inlineParts: [Part]
    public let extractedPromptText: String
    public let warnings: [String]

    public init(inlineParts: [Part] = [], extractedPromptText: String = "", warnings: [String] = []) {
        self.inlineParts = inlineParts
        self.extractedPromptText = extractedPromptText
        self.warnings = warnings
    }
}

public enum AttachmentProcessor {
    public static func process(attachments: [FileAttachment], primarySupportsVision: Bool) async throws -> AttachmentProcessingResult {
        var inlineParts: [Part] = []
        var textBlocks: [String] = []
        var warnings: [String] = []

        for attachment in attachments {
            guard FileManager.default.fileExists(atPath: attachment.fileURL.path) else {
                warnings.append("File not found: \(attachment.filename)")
                continue
            }

            switch attachment.category {
            case .text:
                if let text = try? String(contentsOf: attachment.fileURL, encoding: .utf8) {
                    let truncated = text.count > 100_000 ? String(text.prefix(100_000)) + "\n[Content truncated at 100,000 characters]" : text
                    textBlocks.append("<attached_file name=\"\(attachment.filename)\" mime=\"\(attachment.mimeType)\">\n\(truncated)\n</attached_file>")
                } else {
                    warnings.append("Could not read text from file: \(attachment.filename)")
                }

            case .pdf:
                if let pdf = PDFDocument(url: attachment.fileURL) {
                    var fullPDFText = ""
                    for i in 0..<pdf.pageCount {
                        if let pageText = pdf.page(at: i)?.string {
                            fullPDFText += pageText + "\n"
                        }
                    }
                    let truncated = fullPDFText.count > 100_000 ? String(fullPDFText.prefix(100_000)) + "\n[Content truncated at 100,000 characters]" : fullPDFText
                    textBlocks.append("<attached_file name=\"\(attachment.filename)\" mime=\"application/pdf\">\n\(truncated)\n</attached_file>")
                } else {
                    warnings.append("Could not parse PDF file: \(attachment.filename)")
                }

            case .document:
                if let attrString = try? NSAttributedString(url: attachment.fileURL, options: [:], documentAttributes: nil) {
                    let docText = attrString.string
                    let truncated = docText.count > 100_000 ? String(docText.prefix(100_000)) + "\n[Content truncated at 100,000 characters]" : docText
                    textBlocks.append("<attached_file name=\"\(attachment.filename)\" mime=\"\(attachment.mimeType)\">\n\(truncated)\n</attached_file>")
                } else {
                    warnings.append("Could not read document file: \(attachment.filename)")
                }

            case .image:
                if primarySupportsVision {
                    if let fileData = try? Data(contentsOf: attachment.fileURL) {
                        let base64 = fileData.base64EncodedString()
                        inlineParts.append(Part(inlineData: InlineData(mimeType: attachment.mimeType, data: base64)))
                    } else {
                        warnings.append("Could not read image file: \(attachment.filename)")
                    }
                }

            case .unknown:
                warnings.append("Unsupported file type for attachment: \(attachment.filename)")
            }
        }

        let combinedPromptText = textBlocks.joined(separator: "\n\n")
        return AttachmentProcessingResult(inlineParts: inlineParts, extractedPromptText: combinedPromptText, warnings: warnings)
    }

    public static func categorize(url: URL) -> (AttachmentCategory, String) {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return (.image, "image/png")
        case "jpg", "jpeg": return (.image, "image/jpeg")
        case "gif": return (.image, "image/gif")
        case "webp": return (.image, "image/webp")
        case "pdf": return (.pdf, "application/pdf")
        case "docx": return (.document, "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
        case "rtf": return (.document, "application/rtf")
        case "txt", "md", "json", "csv", "swift", "py", "js", "ts", "html", "css", "sh", "yaml", "yml", "xml":
            return (.text, "text/plain")
        default:
            return (.unknown, "application/octet-stream")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AttachmentProcessorTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/AttachmentProcessor.swift Tests/irisTests/AttachmentProcessorTests.swift
git commit -m "feat: add AttachmentProcessor with native PDFKit and NSAttributedString document parsing

Co-authored-by: Gemini <gemini-cli@google.com>"
```

---

### Task 4: Vision Router & Auxiliary Model Fallback Engine

**Files:**
- Create: `Sources/iris/VisionRouter.swift`
- Modify: `Sources/iris/ConfigManager.swift`
- Create: `Tests/irisTests/VisionRouterTests.swift`

**Interfaces:**
- Consumes: `FileAttachment`, `AuxiliaryModelManager`.
- Produces: Auxiliary image descriptions and model vision capability decisions.

- [ ] **Step 1: Write failing unit test for VisionRouter**

Create `Tests/irisTests/VisionRouterTests.swift`:
```swift
import XCTest
@testable import iris

final class VisionRouterTests: XCTestCase {
    func testPrimaryModelVisionCapabilityDetection() {
        XCTAssertTrue(VisionRouter.isVisionCapable(modelName: "gemini-2.0-flash"))
        XCTAssertTrue(VisionRouter.isVisionCapable(modelName: "claude-3-5-sonnet"))
        XCTAssertTrue(VisionRouter.isVisionCapable(modelName: "gpt-4o"))
        XCTAssertFalse(VisionRouter.isVisionCapable(modelName: "deepseek-r1"))
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter VisionRouterTests`
Expected: FAIL with "cannot find 'VisionRouter' in scope"

- [ ] **Step 3: Implement `VisionRouter.swift` & update `ConfigManager.swift`**

In `ConfigManager.swift`: Add properties for `auxiliaryVisionEngine` and `auxiliaryVisionModel`.

Create `Sources/iris/VisionRouter.swift`:
```swift
import Foundation

public enum VisionRouter {
    public static func isVisionCapable(modelName: String) -> Bool {
        let name = modelName.lowercased()
        if name.contains("gemini") || name.contains("gpt-4o") || name.contains("claude-3") || name.contains("vision") || name.contains("llava") {
            return true
        }
        return false
    }

    public static func processTextOnlyImages(attachments: [FileAttachment]) async -> (descriptionText: String, warnings: [String]) {
        let images = attachments.filter { $0.category == .image }
        guard !images.isEmpty else { return ("", []) }

        let config = ConfigManager.shared
        let auxEngineType = config.auxiliaryVisionEngine
        let auxModelName = config.auxiliaryVisionModel

        if auxEngineType.isEmpty || auxModelName.isEmpty {
            let primaryModel = config.getModel(for: .medium)
            return ("", ["Active model '\(primaryModel)' does not support vision and no auxiliary vision model is configured in Settings."])
        }

        var descriptions: [String] = []
        var warnings: [String] = []

        for img in images {
            do {
                let imgData = try Data(contentsOf: img.fileURL)
                let base64 = imgData.base64EncodedString()
                let prompt = "Describe this image in detail, including text, structure, and visual content, for an AI coding assistant."
                
                // Invoke auxiliary engine (e.g. Ollama)
                let auxiliaryEngine = OllamaEngine()
                let description = try await auxiliaryEngine.generate(prompt: "\(prompt)\n[ImageData: \(base64.prefix(100))...]", jsonSchema: nil)
                
                descriptions.append("<image_description file=\"\(img.filename)\">\n\(description)\n</image_description>")
            } catch {
                warnings.append("Auxiliary vision model failed for \(img.filename): \(error.localizedDescription)")
            }
        }

        return (descriptions.joined(separator: "\n\n"), warnings)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter VisionRouterTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/VisionRouter.swift Sources/iris/ConfigManager.swift Tests/irisTests/VisionRouterTests.swift
git commit -m "feat: add VisionRouter for capability checking and auxiliary vision fallback

Co-authored-by: Gemini <gemini-cli@google.com>"
```

---

### Task 5: Attachment UI & Drag-and-Drop Composer Integration

**Files:**
- Create: `Sources/iris/AttachmentBarView.swift`
- Modify: `Sources/iris/ComposerTextView.swift`
- Modify: `Sources/iris/ChatView.swift`
- Modify: `Sources/iris/MessageItem.swift`
- Modify: `Sources/iris/SettingsView.swift`

**Interfaces:**
- Consumes: `@State var draftAttachments: [FileAttachment]`, `AttachmentProcessor`, `VisionRouter`.
- Produces: Complete macOS UI with attachment chips, 📎 button, drag & drop overlay, and history rendering.

- [ ] **Step 1: Create `AttachmentBarView.swift`**

Create `Sources/iris/AttachmentBarView.swift`:
```swift
import SwiftUI

struct AttachmentChipView: View {
    let attachment: FileAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if attachment.category == .image, let nsImage = NSImage(contentsOf: attachment.fileURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)
            } else {
                Image(systemName: iconName(for: attachment.category))
                    .foregroundColor(.accentColor)
                    .font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(formattedSize(attachment.fileSize))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func iconName(for category: AttachmentCategory) -> String {
        switch category {
        case .pdf: return "doc.richtext"
        case .document: return "doc.text"
        case .text: return "doc.plaintext"
        case .image: return "photo"
        case .unknown: return "paperclip"
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct AttachmentBarView: View {
    @Binding var attachments: [FileAttachment]

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        AttachmentChipView(attachment: attachment) {
                            attachments.removeAll { $0.id == attachment.id }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }
}
```

- [ ] **Step 2: Add 📎 Paperclip button and Drag-and-Drop to `ChatView.swift` & `ComposerTextView.swift`**

In `ChatView.swift`:
1. Add `@State private var draftAttachments: [FileAttachment] = []`.
2. Add `@State private var isDraggingOver = false`.
3. Add `AttachmentBarView(attachments: $draftAttachments)` above `ComposerTextView`.
4. Add 📎 Button in composer toolbar to launch `NSOpenPanel`:
```swift
Button(action: selectAttachments) {
    Image(systemName: "paperclip")
        .font(.system(size: 16))
}
.buttonStyle(.plain)

private func selectAttachments() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    if panel.runModal() == .OK {
        for url in panel.urls {
            let (category, mime) = AttachmentProcessor.categorize(url: url)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let att = FileAttachment(filename: url.lastPathComponent, fileURL: url, mimeType: mime, fileSize: size, category: category)
            draftAttachments.append(att)
        }
    }
}
```
5. Add `.onDrop(of: [.fileURL], isTargeted: $isDraggingOver)` modifier to handle dropped file URLs.
6. When sending a message: pass `draftAttachments` to `ChatMessage` and trigger `AttachmentProcessor.process(...)` and `VisionRouter.processTextOnlyImages(...)`.

- [ ] **Step 3: Update `MessageItem.swift` to render attachments in history**

Update `MessageItem.swift` to check `message.attachments` and render image thumbnails or document chips below/above user text messages.

- [ ] **Step 4: Update `SettingsView.swift` for Auxiliary Vision Model controls**

In `SettingsView.swift`: Add a section under Models for setting the Auxiliary Vision Engine (`ollama`, `cloud`, `none`) and Model Name (`gemma4:12b`, `llama3.2-vision`).

- [ ] **Step 5: Run full build and unit test suite**

Run: `swift test`
Expected: ALL TESTS PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/iris/AttachmentBarView.swift Sources/iris/ChatView.swift Sources/iris/ComposerTextView.swift Sources/iris/MessageItem.swift Sources/iris/SettingsView.swift
git commit -m "feat: complete UI attachment bar, NSOpenPanel integration, drag and drop, and chat history rendering (#15)

Co-authored-by: Gemini <gemini-cli@google.com>"
```
