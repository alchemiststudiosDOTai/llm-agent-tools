# Unified Tool Architecture Pattern

To ensure composability, reliability, and ease of use for LLM agents, all tools in this project must adhere to this unified pattern. This pattern synthesizes the original architecture with the "Chain of Code" state management principles.

## 1. The Interface Contract

Every tool is a standalone Bash script that functions like a well-behaved Unix utility.

### Core Requirements
- **Shebang:** `#!/usr/bin/env bash`
- **Safety:** `set -euo pipefail`
- **Help:** `-h/--help` must render a usage guide.
- **Output:** stdout for data, stderr for logging/errors.
- **Exit Codes:** 0 for success, non-zero for failure.

### Standard Flags
Every tool MUST support these flags where applicable:

| Flag | Long | Description |
| :--- | :--- | :--- |
| `-o` | `--output <FMT>` | Output format: `markdown` (default) or `json`. |
| `-v` | `--verbose` | Enable debug logging to stderr. |
| `-h` | `--help` | Show usage information. |

## 2. Structural Template

```bash
#!/usr/bin/env bash
set -euo pipefail

# [Tool Name] - [Brief Description]
# [Link to docs/reference if applicable]

readonly VERSION="1.0.0"

# Defaults
output_format="markdown"
verbose=false
# ... other tool-specific defaults ...

# Standard Usage Function
usage() {
    cat >&2 <<EOF
[tool-name] v${VERSION} - [Description]

USAGE:
    [tool-name] [COMMAND] [OPTIONS]

COMMANDS:
    [cmd1]          [Description]
    [cmd2]          [Description]

OPTIONS:
    -o, --output <FMT>    Output format: markdown, json (default: markdown)
    -v, --verbose         Enable verbose output
    -h, --help            Show this help

EXAMPLES:
    [tool-name] cmd1 --flag value
EOF
    exit 1
}

# Standard Error Function
die() {
    echo "error: $*" >&2
    exit 1
}

# --- Command Implementations ---

cmd_do_something() {
    # 1. Input Validation
    # 2. Execution
    # 3. Output Formatting (handle $output_format)
}

# --- Main Argument Parsing ---

# 1. Parse Global Options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)
            output_format="$2"
            shift 2
            ;;
        -v|--verbose)
            verbose=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            # Stop if we hit a command-specific flag before the command
            # OR handle as error depending on preference
            break
            ;;
        *)
            # First non-flag is the command
            break
            ;;
    esac
done

[[ $# -eq 0 ]] && usage

command="$1"
shift

# 2. Dispatch Command
case "$command" in
    action1)
        cmd_do_something "$@"
        ;;
    *)
        die "unknown command: $command"
        ;;
esac
```

## 3. Output Standards

Tools must be able to speak "machine" (JSON) and "human" (Markdown).

### JSON Output
- **Must** be valid JSON.
- **Must** be a single object or array (no streaming JSON lines unless explicitly documented).
- **Should** include metadata if complex (e.g., `{"meta": {...}, "data": [...]}`).

### Markdown Output
- **Must** be concise.
- **Should** use headers (`#`, `##`) for structure.
- **Should** use lists for collections.

## 4. State & Context ("Chain of Code")

Tools that manage state (like `scratchpad` or `memory-journal`) must treat state as a first-class citizen.

- **Read-Modify-Write:** Operations should be atomic where possible.
- **History:** Significant state changes should be logged (audit trail).
- **Simulation:** If a tool "simulates" an action (like `scratchpad` tracking variables), it should allow inspecting that state without side effects.

## 5. File System Interaction
- Use `mktemp` for temporary files.
- Cleanup traps for temporary resources.
- Validate paths to prevent directory traversal if accepting file paths.
