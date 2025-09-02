# Claude Knowledge Base

This directory contains the structured knowledge base for AI agents, optimized for fast retrieval using SQLite FTS5.

## Directory Structure

- **metadata/** - Component analysis, system documentation, architecture notes
- **code_index/** - Code relationships, function mappings, type hierarchies
- **debug_history/** - Debug sessions, error fixes, troubleshooting logs
- **patterns/** - Implementation patterns, reusable solutions, best practices
- **qa/** - Questions answered, problems solved with explanations
- **cheatsheets/** - Quick references, common commands, shortcuts
- **delta/** - Change logs, updates, modifications to existing code
- **anchors/** - Important code locations, key files to remember
- **scratchpad/** - Temporary working notes
  - **active/** - Current working notes
  - **archive/** - Completed scratchpad files
- **.rag/** - SQLite FTS5 database and index files

## Usage

### Building the Index
```bash
./claude-rag-lite.sh build
```

### Searching
```bash
./claude-rag-lite.sh query "search term" [limit] [format]
```

### Scratchpad Workflow
```bash
# Create new scratchpad
./scratchpad.sh new task "implement feature"

# Complete and file it
./scratchpad.sh complete task_implement_feature_*.md
./scratchpad.sh filed task_implement_feature_*.md
```

## File Naming Conventions

- Use descriptive names with underscores
- Include dates for time-sensitive content
- Prefix with component/module names when relevant
- Use .md extension for all documentation

## Best Practices

1. Keep files focused on single topics
2. Use clear markdown headers for structure
3. Include code examples where relevant
4. Cross-reference related documents
5. Update regularly as code evolves