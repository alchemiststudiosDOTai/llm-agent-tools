# memory-journal.sh

A lightweight, pure-Markdown project journal. Captures context (Git state, timestamps) in a single `journal.md` file in the current directory.

## Quick Start

```bash
# Add a note
./tools/memory-journal.sh add "Switched to single-file storage" -t "decision"

# List recent notes
./tools/memory-journal.sh list
```

## Commands

```
add <message>       Add a new journal entry
list                List recent entries
search <query>      Search entries by content
```

## Options

```
-n, --num <N>       Number of entries to show (default: 10)
-t, --tags <TAGS>   Comma-separated tags (for add)
-f, --file <PATH>   Journal file path (default: journal.md)
-v, --verbose       Enable verbose output
-h, --help          Show help
```

## Storage

Data is stored in `journal.md` in the current directory by default. 
It is a standard Markdown file that you can edit manually if needed.

Example entry:

```markdown
## 2025-12-16 10:00:00 UTC (`bugfix`)
> Git: main @ a1b2c3d

Fixed race condition in API.

---
```

## Dependencies

- `bash`
- `git` (optional, for context)
