# File Attachments & Vision Routing Design Document

* **Issue**: [#15](https://github.com/bnaylor/iris/issues/15) - Add support for file attachments / uploads
* **Date**: 2026-07-28
* **Status**: Approved

---

## 1. Overview & Goals

Iris needs to support non-text file attachments (images, PDFs, documents, plain text/code files) during user chat sessions. The system must:
1. Provide a native macOS user interface for attaching files via a paperclip 📎 button and drag-and-drop.
2. Render draft attachments as removable chips above the chat composer input field.
3. Automatically process document files (`.pdf`, `.docx`, `.rtf`, `.txt`, `.csv`, `.swift`, etc.) locally via native macOS frameworks (`PDFKit`, `NSAttributedString`).
4. Route image attachments according to active model capabilities:
   - Pass raw binary payloads natively to vision-capable primary models (Gemini, Claude 3.5/3.7, GPT-4o).
   - Automatically fall back to an auxiliary vision model (e.g. Ollama `gemma4:12b` or `llama3.2-vision`) when the primary model is text-only.
   - Display a clean warning notification if the primary model is text-only and no auxiliary vision model is configured.

---

## 2. Architecture & Data Models

### 2.1 Data Models (`AppState.swift`)

```swift
public enum AttachmentCategory: String, Codable {
    case image
    case pdf
    case document // docx, rtf
    case text     // txt, md, json, csv, source code
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
```

* `ChatMessage` update:
  - Add `var attachments: [FileAttachment] = []`.
  - Ensure backwards compatibility: `attachments` is optional during JSON decoding with a default value of `[]`.

### 2.2 API Serialization (`Models.swift`, `LLMClient.swift`, `OpenAIClient.swift`, `AnthropicClient.swift`)

```swift
public struct InlineData: Codable {
    public let mimeType: String
    public let data: String // Base64 encoded string
}

public struct Part: Codable {
    public var text: String?
    public var inlineData: InlineData?
    public var functionCall: FunctionCall?
    public var functionResponse: FunctionResponse?
    public var thought_signature: String?
    public var thoughtSignature: String?
}
```

* **Gemini Adapter**: Maps `Part.inlineData` directly to Gemini REST payload `{ "inlineData": { "mimeType": "...", "data": "..." } }`.
* **OpenAI Adapter**: Maps `Part.inlineData` images to `image_url` parts formatted as `data:image/...;base64,...`.
* **Anthropic Adapter**: Maps `Part.inlineData` images to Anthropic's image source block format `{ "type": "image", "source": { "type": "base64", "media_type": "...", "data": "..." } }`.

---

## 3. Attachment Processing & Vision Router

### 3.1 `AttachmentProcessor.swift`

Handles content extraction and payload assembly before dispatch:

```swift
public struct AttachmentProcessingResult {
    public let inlineParts: [Part]            // Image inline parts for multimodal models
    public let extractedPromptText: String    // Formatted text prefix containing extracted documents and image descriptions
    public let warnings: [String]             // User notification messages
}
```

1. **Document Text Extraction**:
   - `.pdf`: Uses `PDFKit` (`PDFDocument(url:)`) to extract plain text across pages.
   - `.docx`, `.rtf`: Uses `NSAttributedString(url:options:documentAttributes:)` for document reading.
   - Plain text & code (`.txt`, `.md`, `.json`, `.csv`, `.swift`, etc.): Reads UTF-8 text string directly.
   - Text is formatted into prompt prefix:
     ```
     <attached_file name="doc.pdf" mime="application/pdf">
     [Extracted document content...]
     </attached_file>
     ```

### 3.2 Vision Router (`VisionRouter.swift`)

1. **Primary Model Capability Check**: Determines if active primary model supports vision (`Gemini`, `Claude`, `GPT-4o`, or explicit vision-capable local model).
2. **Vision-Capable Primary Model**: Base64 encodes image file data and generates `Part(inlineData: InlineData(...))`.
3. **Text-Only Primary Model**:
   - Queries `AuxiliaryModelManager` for configured auxiliary vision engine/model (e.g., `Ollama` with model `gemma4:12b` or `llama3.2-vision`).
   - **Configured**: Sends image + prompt to auxiliary vision model (*"Describe this image in detail..."*), inserting the resulting text as:
     ```
     <image_description file="photo.png">
     [Generated visual description]
     </image_description>
     ```
   - **Not Configured**: Generates warning string: *"Active model does not support vision and no auxiliary vision model is configured in Settings."* and displays a toast notification in chat.

---

## 4. UI Components & Interaction

1. **`AttachmentBarView.swift`**:
   - Positioned above `ComposerTextView` inside `ChatView`.
   - Horizontal `ScrollView` containing `AttachmentChipView`s.
   - Images render thumbnail preview (36x36). Documents render icon, filename, and size. Hoverable `x` button detaches item.
2. **Attachment 📎 Button**:
   - Positioned in input control bar. Launches native `NSOpenPanel` (`allowsMultipleSelection = true`).
3. **Drag & Drop Target**:
   - `.onDrop(of: [.fileURL], isTargeted: $isDraggingOver)` on `ChatView`.
   - Displays semi-transparent accent overlay with dashed border and *"Drop files here to attach"* text when dragging files.
4. **Chat Message History**:
   - `MessageItem.swift` renders attachment thumbnails/pills under user messages in history.

---

## 5. Settings Integration, Edge Cases & Error Handling

1. **Settings**:
   - Adds **Auxiliary Vision Engine** configuration under Settings > Models (Engine type and Model name).
2. **File Size Limits**:
   - Maximum 20 MB for images, 50 MB for documents. Surface warning if exceeded.
3. **Large Document Truncation**:
   - Truncates extracted text exceeding 100,000 characters with notice: `[Content truncated at 100,000 characters]`.
4. **Unreadable/Corrupted Files**:
   - Catches decoding failures and displays non-blocking toast warning.

---

## 6. Testing Plan

* **`AttachmentProcessorTests.swift`**:
  - Test PDF parsing with fixture `.pdf`.
  - Test `.docx` / `.txt` / `.swift` text extraction.
  - Test base64 image encoding and `Part` payload conversion.
* **`VisionRouterTests.swift`**:
  - Test routing decision tree for vision-capable vs text-only models.
  - Mock auxiliary vision model response generation and warning flag creation.
* **`ChatMessageSerializationTests.swift`**:
  - Test JSON serialization/deserialization of `ChatMessage` with attachments.
  - Verify backwards compatibility for legacy JSON payloads without `attachments` key.
