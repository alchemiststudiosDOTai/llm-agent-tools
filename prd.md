Here’s a **Mermaid flowchart** version for the new **Bash + Python (SQLite FTS5) RAG system** integrated into your existing `.claude/` workflow.

```mermaid
flowchart TD
    A([Start: User/Agent]) --> B{Action Needed?}

    B -->|New Task| S1["`**SCRATCHPAD PHASE**
    ./scratchpad.sh new
    Notes & raw thoughts in active/`"]

    B -->|Search Docs| R1["`**RAG PHASE**
    ./claude-rag-lite.sh query
    Compact FTS5 retrieval`"]

    B -->|Update Index| R2["`**INDEX PHASE**
    ./claude-rag-lite.sh build
    Incremental SQLite index`"]

    S1 --> S2["`**Complete & File**
    ./scratchpad.sh complete → filed
    Move to .claude/[dir]`"]

    S2 --> R2
    R2 --> R3[("`**SQLite FTS5 DB**
    - docs table (path,cat,title)
    - docs_fts (fulltext)
    - map(doc_id→fts_rowid)`")]

    R1 --> R4["`**Search Results**
    - JSONL or text
    - Compact snippets
    - ≤ N chars for context`"]

    R4 --> S3["`**Agent Context**
    Use only compact results
    Summarize → Plan → Code`"]

    subgraph CLAUDE_DIR[.claude Knowledge Base]
        M1[metadata/]:::d
        C1[code_index/]:::d
        D1[debug_history/]:::d
        P1[patterns/]:::d
        Q1[qa/]:::d
        CH1[cheatsheets/]:::d
        DL1[delta/]:::d
        AN1[anchors/]:::d
        SCR1[scratchpad/archive]:::d
    end

    classDef d fill:#1976d2,stroke:#0d47a1,stroke-width:2px,color:#fff
    classDef r fill:#388e3c,stroke:#1b5e20,stroke-width:2px,color:#fff
    classDef s fill:#f57c00,stroke:#e65100,stroke-width:2px,color:#fff

    CLAUDE_DIR --> R2
    R3:::r --> R1
    R1 --> S3:::s
```

---

### How to Use the Chart

1. **Scratchpad Phase** → Take notes as usual, file them into `.claude/` when ready.
2. **Index Phase** → `./claude-rag-lite.sh build` keeps SQLite FTS5 index updated incrementally.
3. **Search Phase** → `./claude-rag-lite.sh query "term"` returns compact JSON/text snippets for clean context injection.
4. **Agent Context** → Agent only sees **compacted info**, not raw full files, keeping the prompt window clean.

---
