# Rust RAG Search

Fast FTS5 search tool for SQLite knowledge bases. This is a high-performance Rust implementation focused on fast search operations.

## Features

- **Fast**: Built in Rust with optimized release profile
- **FTS5 Support**: Full-text search using SQLite FTS5 with BM25 ranking
- **Multiple Output Formats**: JSONL (compact), JSON (pretty), and human-readable text
- **Category Filtering**: Search within specific categories
- **Smart Snippets**: Extracts relevant context around search terms
- **CLI**: Simple command-line interface with `clap`

## Building

### Prerequisites
- Rust 1.70+ (install from [rustup.rs](https://rustup.rs))

### Build Release Binary

```bash
cd rust-rag
cargo build --release
```

The optimized binary will be at `target/release/rust-rag-search`

### Quick Build (Debug)

```bash
cargo build
```

## Usage

### Basic Search

```bash
./target/release/rust-rag-search \
  --db-path /path/to/knowledge.db \
  --query "your search query"
```

### Search Options

```bash
rust-rag-search [OPTIONS] --db-path <DB_PATH> --query <QUERY>

Options:
  -d, --db-path <DB_PATH>          Path to SQLite database
  -q, --query <QUERY>              Search query
  -l, --limit <LIMIT>              Maximum number of results [default: 10]
  -s, --max-snippet <MAX_SNIPPET>  Maximum snippet length [default: 500]
  -f, --format <FORMAT>            Output format [default: jsonl] [possible values: json, jsonl, text]
  -c, --category <CATEGORY>        Search specific category only
  -h, --help                       Print help
```

### Examples

#### JSONL Output (Compact, for agents)
```bash
./target/release/rust-rag-search \
  --db-path ../knowledge_base/kb.db \
  --query "authentication" \
  --format jsonl \
  --limit 5
```

#### JSON Output (Pretty)
```bash
./target/release/rust-rag-search \
  --db-path ../knowledge_base/kb.db \
  --query "error handling" \
  --format json
```

#### Text Output (Human-readable)
```bash
./target/release/rust-rag-search \
  --db-path ../knowledge_base/kb.db \
  --query "database connection" \
  --format text
```

#### Category-Specific Search
```bash
./target/release/rust-rag-search \
  --db-path ../knowledge_base/kb.db \
  --query "api endpoints" \
  --category "backend"
```

## Performance

The release build is optimized for speed with:
- LTO (Link Time Optimization)
- Single codegen unit for maximum optimization
- Stripped symbols for smaller binary size
- Opt-level 3

Typical search performance: **< 10ms** for most queries on databases with thousands of documents.

## Output Formats

### JSONL (Default)
Compact format, one JSON object per line:
```json
{"p":"/path/to/doc","c":"category","t":"title","s":"snippet...","r":-0.5}
```

### JSON
Pretty-printed with metadata:
```json
{
  "query": "search term",
  "count": 2,
  "results": [
    {
      "path": "/path/to/doc",
      "category": "category",
      "title": "Document Title",
      "snippet": "...relevant snippet...",
      "rank": -0.5
    }
  ]
}
```

### Text
Human-readable format with numbered results.

## Integration with Python Tools

This Rust search tool works with databases created by the Python indexing tools in `../rag_modules/`. It only performs search operations - indexing should still be done with the Python tools.

## License

Same as parent project.
