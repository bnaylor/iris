# scromp

open source local memory providers llm agents

# gemini

Mem0, OpenMemory, Letta, and Graphiti are the top open-source, local memory providers for Large Language Model (LLM) agents. Unlike simple vector databases, these systems act as intelligent cognitive layers. They automatically extract, structure, update, and deprecate facts from conversation histories entirely on your own local hardware. [1, 2, 3, 4, 5] 
------------------------------
## Top Open-Source Local Memory Providers## 1. Mem0 (The All-Around Standard)

* Best For: General-purpose personalized AI assistants and multi-agent systems. [2, 6, 7, 8] 
* How It Works: Mem0 extracts preferences, user traits, and organizational facts from conversations. It passes new details through a distillation process. Instead of deleting old data, it gracefully deprecates it to keep long-term context intact. [2, 4] 
* Local Stack: Runs locally using a Python environment, storing data in SQLite, a custom graph DB, or PostgreSQL with pgvector. It natively links with local LLM engines like Ollama, LM Studio, and LiteLLM. [4, 9, 10] 
* Project Page: Check out the official repository via Mem0 on GitHub. [11, 12] 

## 2. OpenMemory (Cognitive & MCP-Ready)

* Best For: Advanced developers needing standard Model Context Protocol (MCP) integrations with local development tools. [3, 13] 
* How It Works: OpenMemory provides multi-sector cognitive structures. It divides memory into distinct episodic (events), semantic (facts), procedural (skills), emotional, and reflective layers. [3] 
* Local Stack: Operates via Python and Node SDKs using local SQLite or PostgreSQL backends. It features native plug-and-play integrations for [LangChain](https://www.langchain.com/) and CrewAI. [3] 
* Project Page: Review the open-source code at [OpenMemory on GitHub](https://github.com/CaviraOSS/OpenMemory). [14] 

## 3. Letta (Stateful & Self-Editing Memory)

* Best For: Creating long-lived autonomous agents with advanced context window management.
* How It Works: Letta (formerly MemGPT) uses a multi-tier memory hierarchy (Core, In-Context, and Archival). Agents are given tools to explicitly edit, append, and organize their own long-term memory blocks.
* Local Stack: Completely self-hosted, allowing your agent's state to persist across restarts while executing local tool calls. [1, 15, 16, 17, 18] 

## 4. Graphiti (Temporal Knowledge Graphs)

* Best For: Complex, multi-hop reasoning over timeline-dependent facts.
* How It Works: Graphiti structures information strictly into a temporal graph. It continuously updates the edge relationships between entities as time moves forward. This prevents your agent from acting on outdated constraints.
* Local Stack: Built by the team at Zep, it supports local LLMs via Ollama and requires a local graph storage backend such as Neo4j or KuzuDB. [4, 6, 19, 20, 21] 

------------------------------
## Comparison of Local Architecture Options

| Memory Provider | Storage Architecture | Memory Extraction Style | Local Compatibility |
|---|---|---|---|
| Mem0 | Hybrid (Vector, SQL, Graph) | Key-value semantic facts | High (Ollama, LM Studio) |
| OpenMemory | Multi-sector (SQLite/Postgres) | Cognitive sectors (Episodic, Semantic) | High (MCP Protocol, Local Dev Tools) |
| Letta | Tiered/Hierarchical Cache | Agent self-editing blocks | High (Stateful agent persistence) |
| Graphiti | Temporal Graph (Neo4j, KuzuDB) | Time-aware relationship edges | Medium (Requires graph database setup) |

------------------------------
## How to Choose a Local Memory Stack

   1. If you want simple setup and lightweight code integration, deploy Mem0 with a local SQLite file.
   2. If you are building code assistants or IDE agents, use OpenMemory due to its built-in MCP protocol support.
   3. If your agent needs to decide what to remember on its own, use Letta's self-editing memory blocks.
   4. If your data changes rapidly over time (e.g., calendar scheduling, task statuses), use Graphiti to track factual timelines. [1, 2, 3, 4, 22] 

To help narrow down the right stack, tell me:

* What agent framework are you using (e.g., Custom scripts, LangGraph, CrewAI, AutoGen)?
* What local LLM engine runs your models (e.g., Ollama, LM Studio, vLLM)?
* What hardware constraints do you have for running background databases? [4, 23, 24, 25, 26] 


[1] [https://medium.com](https://medium.com/@jununhsu/6-open-source-ai-memory-tools-to-give-your-agents-long-term-memory-39992e6a3dc6)
[2] [https://www.cognee.ai](https://www.cognee.ai/blog/guides/best-open-source-ai-memory-tools-for-llm-agents-and-developers)
[3] [https://dev.co](https://dev.co/ai/frameworks/openmemory)
[4] [https://www.infoworld.com](https://www.infoworld.com/article/4192397/four-agentic-ai-memory-systems-for-smarter-llms.html)
[5] [https://medium.com](https://medium.com/@sahin.samia/building-long-term-agent-memory-with-mem0-langgraph-308ef4970699)
[6] [https://get-hermes.ai](https://get-hermes.ai/memory/)
[7] [https://mem0.ai](https://mem0.ai/blog/mem0-vs-zep)
[8] [https://techsy.io](https://techsy.io/en/blog/best-ai-agent-memory-tools)
[9] [https://railway.com](https://railway.com/deploy/mem0)
[10] [https://garden3d.substack.com](https://garden3d.substack.com/p/where-the-flower-grows)
[11] [https://openreview.net](https://openreview.net/forum?id=k5nIOvYGCL)
[12] [https://arxiv.org](https://arxiv.org/html/2601.01885v1)
[13] [https://www.instagram.com](https://www.instagram.com/reel/DIu76FoI9v5/)
[14] [https://github.com](https://github.com/CaviraOSS/OpenMemory)
[15] [https://fast.io](https://fast.io/resources/top-10-open-source-ai-agents/)
[16] [https://www.cognee.ai](https://www.cognee.ai/blog/guides/best-open-source-ai-memory-tools-for-llm-agents-and-developers)
[17] [https://powerdrill.ai](https://powerdrill.ai/blog/best-free-memory-layer-for-coding-agents)
[18] [https://atlan.com](https://atlan.com/know/best-ai-agent-memory-frameworks-2026/)
[19] [https://arxiv.org](https://arxiv.org/html/2512.12967v1)
[20] [https://arxiv.org](https://arxiv.org/html/2410.20299v2)
[21] [https://theneuralmaze.substack.com](https://theneuralmaze.substack.com/p/building-agent-memory-with-knowledge)
[22] [https://www.cognee.ai](https://www.cognee.ai/blog/guides/best-ai-memory-layers-for-ai-agents-in-2026-comparison)
[23] [https://mem0.ai](https://mem0.ai/blog/memory-layer-for-open-source-agent-frameworks)
[24] [https://www.sitepoint.com](https://www.sitepoint.com/the-complete-stack-for-local-autonomous-agents--from-ggml-to-orchestration/)
[25] [https://www.patronus.ai](https://www.patronus.ai/ai-agent-development)
[26] [https://pmc.ncbi.nlm.nih.gov](https://pmc.ncbi.nlm.nih.gov/articles/PMC11235180/)


# scromp

I'm building my own agentic harness, and I'd like to add a memory layer in between the "working context" and the long-term markdown file library that particularly enables just-in-time fact searching.  I use HRR/Holographic with Hermes, and Mem0 seems interesting too.  But this harness is written in Swift and I don't want to pull in a bunch of npm/python dependencies.  Nor cloud services.  I'd like a locally-hosted, relatively simple fact store.  Vector, sqlite, whatever.  Store facts, relate them to each other, search for them, maybe rank/trust metrics.  What are my options?

# gemini

Building a pure Swift, dependency-free agentic harness means you want to avoid bloated Python or Node microservices running in the background. Because you are using a Holographic/HRR (Holographic Reduced Representation) concept with Hermes, you need a high-speed, lightweight intermediary bridge that connects raw textual fact extraction with your final long-term markdown files. [1, 2] 
To accomplish this entirely inside native Swift (targeting macOS or iOS) without any npm, python, or cloud overhead, several local architectural options stand out. [3] 
------------------------------
## Native Swift & Embedded Fact Store Options## 1. SQLite with GRDB (The Graph + Relational Approach) [4] 
Since you want to relate facts to each other and track metrics (like trust or ranking), a relational structure is ideal. Instead of pulling in massive frameworks, you can construct a simple semantic graph using native SQLite via [GRDB.swift](https://github.com/groue/GRDB.swift).

* How to build it: Create a facts table and a fact_relations table.

CREATE TABLE facts (
    id TEXT PRIMARY KEY,
    content TEXT NOT NULL,
    trust_score REAL DEFAULT 1.0,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE fact_relations (
    source_id TEXT,
    target_id TEXT,
    relation_type TEXT, -- e.g., "contradicts", "supports", "refines"
    weight REAL DEFAULT 1.0,
    PRIMARY KEY (source_id, target_id),
    FOREIGN KEY(source_id) REFERENCES facts(id),
    FOREIGN KEY(target_id) REFERENCES facts(id)
);


* For Just-In-Time (JIT) Search: Pair SQLite's built-in FTS5 (Full-Text Search) extension for keyword lookup with raw cosine-similarity filtering in Swift if your embeddings are small.
* Why it fits: It is incredibly lightweight, compiled directly into your Swift binary, requires zero external server setup, and perfectly maps trust scores and edge relations. [5] 

## 2. SQLite-Vector (The C-Extension Route) [6] 
If you want hardware-accelerated semantic search embedded straight into your SQLite file without external daemons, you can compile the open-source [sqlite-vector extension](https://github.com/sqliteai/sqlite-vector) directly into your app. [7] 

* How it works: It treats embeddings as standard BLOB columns inside ordinary SQLite tables. It supports Float32/Float16 vector properties and uses highly optimized SIMD instruction sets tailored for Apple Silicon (Accelerate framework). [7, 8, 9] 
* Why it fits: Zero preprocessing or heavy vector indexes like HNSW are required for fast, localized search datasets. You can execute a single SQL query that ranks facts by a combination of vector similarity and your custom trust_score column. [8, 10] 

## 3. ObjectBox Swift (The Ready-Made Local Vector DB)
If you do not want to write raw SQL schemas but still require high-performance, on-device vector search, [ObjectBox Swift](https://objectbox.io/swift-ios-on-device-vector-database-aka-semantic-index/) is an open-source, embedded object database designed for offline-first edge AI. [11, 12] 

* How it works: It runs completely inside your app process. You simply define a Swift class (e.g., Fact) and mark your embedding arrays with an @HNSW index. [11, 13, 14] 
* Why it fits: It is incredibly fast (written in C/C++ with a clean Swift wrapper). It allows you to freely add standard properties like var trustScore: Double and var relatedFactIds: [String] directly to your Swift entities. [12, 13] 

## 4. VecturaKit (Pure Swift Framework) [15] 
[VecturaKit](https://github.com/rryam/VecturaKit) is a lightweight, Swift-based vector database specifically engineered for on-device applications. [15] 

* How it works: It provides a unified local storage wrapper. It can plug directly into Apple's native NLContextualEmbedder (from the built-in NaturalLanguage framework). This allows you to generate vectors completely offline with zero external model dependencies. [15, 16, 17] 
* Why it fits: It provides a pure, idiomatic Swift architecture without requiring external database servers or complex compilation pipelines. [15, 18] 

------------------------------
## Recommended Hybrid Architecture for Your Harness
Because your system bridges dynamic "working memory" with permanent markdown libraries, the most robust option for an agentic harness is a local relational graph using SQLite + FTS5 + Apple's CoreML/NaturalLanguage framework.

[ Working Context ] 
       │
       ▼ (Just-In-Time Query)
┌────────────────────────────────────────────────────────┐
│  Local SQLite Cache Layer                              │
│  - Facts Table (with trust_score, timestamp)           │
│  - Edges Table (defines links between facts)          │
│  - FTS5 Virtual Table (instant keyword indexing)       │
└────────────────────────────────────────────────────────┘
       ▲
       │ (Hydration / Archival)
[ Markdown File Library ]

## How to Implement Just-In-Time Ranking & Trust Metrics
By using SQLite, you can write a simple custom ranking algorithm in Swift that blends multiple signals into a single score: [19] 
$$\text{Final Rank} = (W_1 \times \text{Semantic/Lexical Score}) + (W_2 \times \text{Trust Metric}) + (W_3 \times \text{Recency Reciprocal})$$ 
This setup keeps your working memory layer extremely fast. It operates on an isolated file on disk, allows Hermes to establish relational associations easily, and avoids dependency bloat.
------------------------------
To refine this approach for your harness, let me know:

* How are you currently generating your vector embeddings in Swift (e.g., via a local CoreML / NLContextualEmbedder model, or calling a local endpoint like Ollama)?
* Roughly how many distinct facts do you expect this intermediate JIT store to hold at any given time before archiving them out to markdown? [15, 20, 21] 


[1] [https://hindsight.vectorize.io](https://hindsight.vectorize.io/guides/2026/04/21/guide-hermes-agent-holographic-memory-technical-deep-dive)
[2] [https://www.reddit.com](https://www.reddit.com/r/ClaudeAI/comments/1udlp4z/memory_layer_situation_in_claude_and_other/)
[3] [https://swiftprogramming.com](https://swiftprogramming.com/best-ai-coding-agent-xcode/)
[4] [https://medium.com](https://medium.com/hackernoon/unexpected-sqlite-with-swift-ddc6343bcbfc)
[5] [https://www.reddit.com](https://www.reddit.com/r/AI_Agents/comments/1uas6nb/openai_agent_sdk_vs_hermes_vs_pi_vs_openclaw/)
[6] [https://www.sitepoint.com](https://www.sitepoint.com/local-first-rag-vector-search-in-sqlite-with-hamming-distance/)
[7] [https://github.com](https://github.com/sqliteai/sqlite-vector)
[8] [https://github.com](https://github.com/sqliteai/sqlite-vector)
[9] [https://www.sqlite.ai](https://www.sqlite.ai/sqlite-vector)
[10] [https://codelabs.developers.google.com](https://codelabs.developers.google.com/agentverse-dataengineer/instructions)
[11] [https://objectbox.io](https://objectbox.io/swift-ios-on-device-vector-database-aka-semantic-index/)
[12] [https://github.com](https://github.com/objectbox/objectbox-swift)
[13] [https://www.reddit.com](https://www.reddit.com/r/swift/comments/1l8ws6t/ondevice_vectordb_options_for_foundation_models/)
[14] [https://medium.com](https://medium.com/@softtrainee.pss/how-to-build-a-robust-ios-app-with-swiftdata-a-comprehensive-guide-9acb3bf09299)
[15] [https://github.com](https://github.com/rryam/VecturaKit)
[16] [https://www.markus-schall.de](https://www.markus-schall.de/en/2025/08/ollama-meets-qdrant-a-local-memory-for-your-ki-on-the-mac/)
[17] [https://www.preprints.org](https://www.preprints.org/manuscript/202510.0924)
[18] [https://www.reddit.com](https://www.reddit.com/r/LocalLLaMA/comments/1qtdejw/i_built_a_swiftnative_singlefile_memory_engine/)
[19] [https://promptguard.co](https://promptguard.co/blog/hybrid-detection-architecture)
[20] [https://kotrotsos.medium.com](https://kotrotsos.medium.com/the-local-ai-stack-for-apple-silicon-now-with-superpowers-c6038147eb1a)
[21] https://sharpvector.build5nines.com


