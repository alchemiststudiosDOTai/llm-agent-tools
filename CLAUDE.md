# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an integrated toolkit for LLM agents that combines temporary workspace management (scratchpad) with persistent knowledge retrieval (RAG). The tools are designed to work together in a continuous cycle where each task builds on previous knowledge.

## Critical Workflow - ALWAYS USE BOTH TOOLS TOGETHER

The scratchpad and RAG tools are NOT alternatives - they work in conjunction:

1. **Start every task with BOTH:**
   ```bash
   ./scratchpad.sh new [type] "description"  # Create workspace
   ./claude-rag-lite.sh query "search terms"  # Search existing knowledge
   ```

2. **During work:** Continuously append findings to scratchpad and search RAG for patterns

3. **Complete the cycle:**
   ```bash
   ./scratchpad.sh complete [filename]  # Get filing instructions
   ./scratchpad.sh filed [filename]     # Mark as filed
   ./claude-rag-lite.sh build          # Update RAG index
   ```

## Commands

### Knowledge Base Management
```bash
# Initialize/update RAG index (run after adding new docs to .claude/)
./claude-rag-lite.sh build

# Search knowledge base
./claude-rag-lite.sh query "search terms" [limit] [format]
# Formats: json (default), text, markdown

# View index statistics
./claude-rag-lite.sh stats
```

### Scratchpad Workflow
```bash
# Create scratchpad (types: task, debug, plan, general)
./scratchpad.sh new [type] "description"

# Work with scratchpads
./scratchpad.sh list [filter]
./scratchpad.sh view <filename>
./scratchpad.sh append <filename> "text to add"

# Complete and file
./scratchpad.sh complete <filename>  # Shows filing instructions
./scratchpad.sh filed <filename>     # Removes after filing
```

### Python Environment
```bash
# Uses uv for dependency management (stdlib only, no external deps)
# Virtual env auto-created on first run
# Manual setup if needed:
uv venv
uv run python3 rag_modules/indexer.py --claude-dir .claude --db-path .claude/.rag/claude_knowledge.db
```

## Architecture

### Knowledge Flow Pipeline
```
scratchpad (temp work) → .claude/[category]/ → RAG index → searchable knowledge
```

### Directory Structure
- `.claude/` - Knowledge base root
  - `metadata/` - System architecture, dependencies
  - `code_index/` - Function mappings, type hierarchies  
  - `debug_history/` - Past debugging sessions and fixes
  - `patterns/` - Reusable implementation patterns
  - `qa/` - Answered questions with explanations
  - `cheatsheets/` - Quick command references
  - `delta/` - Change logs and updates
  - `anchors/` - Important code locations
  - `scratchpad/active/` - Current working notes
  - `.rag/claude_knowledge.db` - SQLite FTS5 index

### Key Components
- `scratchpad.sh` - Bash script managing temporary workspaces
- `claude-rag-lite.sh` - Bash wrapper for RAG system
- `rag_modules/indexer.py` - Builds SQLite FTS5 index
- `rag_modules/search.py` - Queries the index
- `rag_modules/stats.py` - Shows index statistics

## Important Implementation Details

1. **SQLite FTS5** - Uses full-text search with SQLite, no external dependencies
2. **Incremental Indexing** - Only indexes new/modified files
3. **Category Detection** - Automatically categorizes docs based on directory
4. **Snippet Length** - Controlled by MAX_SNIPPET_LENGTH env var (default: 500)
5. **Python Stdlib Only** - No pip packages needed, uses only Python standard library

## When Working on Tasks

1. ALWAYS create a scratchpad first
2. ALWAYS search existing knowledge before implementing
3. Document connections to existing solutions in scratchpad
4. File completed work to appropriate .claude/ directory
5. Rebuild RAG index after filing to make knowledge searchable

## Environment Variables
- `MAX_SNIPPET_LENGTH` - RAG snippet size (default: 500)
- `DEFAULT_LIMIT` - RAG result limit (default: 10)
- `EDITOR` - Editor for scratchpad editing (default: nano)
- `CLAUDE_AGENT_ID` - Agent identifier in scratchpads