# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CRITICAL WORKFLOW THAT MUST ALWAYS BE FOLLOWED

The scratchpad and RAG tools create a knowledge-building system. **ALWAYS follow this workflow:**

```bash
# Start any task
./scratchpad.sh scaffold [task_name]
./claude-rag-lite.sh query "[related terms]"

# During work
./scratchpad.sh append [research|plan|implement]_*.md "progress note"
./claude-rag-lite.sh query "error or pattern I need"

# Complete work
./scratchpad.sh fileto [file] [directory] [new_name]
./scratchpad.sh delta "Feature Name" "what changed"
./claude-rag-lite.sh build

# Verify it's searchable
./claude-rag-lite.sh query "what I just built"
```

**This cycle ensures every piece of work becomes reusable knowledge for the entire team.**
This keeps a system for developers and other agents in the future and is a separate system from main project documentation.

## Project Overview

This is an integrated toolkit for LLM agents that combines temporary workspace management (scratchpad) with persistent knowledge retrieval (RAG). The tools are designed to work together in a continuous cycle where each task builds on previous knowledge.

## The Three-Phase Workflow

### 1. RESEARCH PHASE
- Create scaffold: `./scratchpad.sh scaffold [task_name]`
- Search ALL existing knowledge first
- Document what you find in `research_*.md`
- Identify gaps and existing patterns

### 2. PLAN PHASE  
- Based on research, create explicit plan in `plan_*.md`
- List specific files, steps, and acceptance criteria
- Reference existing patterns found during research

### 3. IMPLEMENT PHASE
- Execute the plan step by step
- Document progress and decisions in `implement_*.md`
- Search for solutions when hitting issues
- Test after each component

## Commands Reference

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

# Scaffold creates research/plan/implement structure
./scratchpad.sh scaffold [task_name]

# Work with scratchpads
./scratchpad.sh list [filter]
./scratchpad.sh view <filename>
./scratchpad.sh append <filename> "text to add"

# Complete and file
./scratchpad.sh complete <filename>  # Shows filing instructions
./scratchpad.sh fileto <filename> <dir> [new_name]  # File to .claude/[dir]/
./scratchpad.sh filed <filename>     # Mark as filed and remove
./scratchpad.sh delta <title> [summary]  # Create timestamped change log
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

## Best Practices

1. **ALWAYS search before coding** - Someone may have solved it already
2. **Document as you go** - Append to scratchpads during work, not after
3. **File knowledge immediately** - Don't let scratchpads pile up
4. **Use meaningful names** - When filing with `fileto`, use descriptive names
5. **Create debug entries** - Document every bug fix for future reference
6. **Update the index** - Run `./claude-rag-lite.sh build` after filing

## Environment Variables
- `MAX_SNIPPET_LENGTH` - RAG snippet size (default: 500)
- `DEFAULT_LIMIT` - RAG result limit (default: 10)
- `EDITOR` - Editor for scratchpad editing (default: nano)
- `CLAUDE_AGENT_ID` - Agent identifier in scratchpads