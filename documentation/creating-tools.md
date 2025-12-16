# Creating Bash Tools

Guide for adding new tools to this project.

## File Structure

```
tools/
└── your-tool.sh          # The script

documentation/
└── your-tool.md          # Tool docs
```

## Script Template

```bash
#!/usr/bin/env bash
set -euo pipefail

# your-tool - One line description
# https://api-docs-url.com (if applicable)

readonly VERSION="1.0.0"

# Defaults
option_one="default"
verbose=false

usage() {
    cat >&2 <<EOF
your-tool v${VERSION} - Short description

USAGE:
    your-tool [OPTIONS] <required-arg>

OPTIONS:
    -o, --option <VAL>    Description (default: ${option_one})
    -v, --verbose         Enable verbose output
    -h, --help            Show this help

ENVIRONMENT:
    YOUR_API_KEY          Required if using an API

EXAMPLES:
    your-tool "basic usage"
    your-tool -o value "with option"
EOF
    exit 1
}

die() {
    echo "error: $*" >&2
    exit 1
}

# Parse arguments
positional=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--option)
            option_one="$2"
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
            die "unknown option: $1"
            ;;
        *)
            positional="$1"
            shift
            ;;
    esac
done

# Validate
[[ -z "$positional" ]] && usage

# Main logic
main() {
    # Your code here
    echo "Running with: $positional"
}

main
```

## Conventions

### Error Handling

```bash
# Always use set -euo pipefail
set -euo pipefail

# Use die() for fatal errors
die() {
    echo "error: $*" >&2
    exit 1
}

# Check required env vars early
[[ -z "${API_KEY:-}" ]] && die "API_KEY not set"
```

### Output

```bash
# Normal output to stdout (for agents to consume)
echo "result data"

# Errors and debug info to stderr
echo "debug: processing..." >&2

# Use jq for JSON formatting
curl -s "$url" | jq .
```

### Dependencies

Keep minimal. Prefer:
- `curl` for HTTP
- `jq` for JSON
- Standard coreutils

If you need something else, document it.

### Arguments

```bash
# Short and long forms
-n, --num       # with value
-v, --verbose   # flag only

# Positional args last
your-tool [OPTIONS] <query>
```

### API Keys

```bash
# Read from environment
readonly API_KEY="${YOUR_API_KEY:-}"

# Validate early
[[ -z "$API_KEY" ]] && die "YOUR_API_KEY environment variable not set"

# Use in headers
curl -H "Authorization: Bearer $API_KEY" ...
```

## Documentation Template

Create `documentation/your-tool.md`:

```markdown
# your-tool.sh

One line description.

## Quick Start

\`\`\`bash
export YOUR_API_KEY=xxx
./tools/your-tool.sh "query"
\`\`\`

## Options

\`\`\`
-o, --option <VAL>    Description
-v, --verbose         Enable verbose output
-h, --help            Show help
\`\`\`

## Examples

\`\`\`bash
# Basic
./tools/your-tool.sh "example"

# With options
./tools/your-tool.sh -o value "example"
\`\`\`

## Output

Describe output format (markdown, JSON, etc).

## Dependencies

- curl
- jq
```

## Checklist

Before submitting:

- [ ] Script is executable (`chmod +x`)
- [ ] `set -euo pipefail` at top
- [ ] `-h/--help` works
- [ ] Errors go to stderr
- [ ] Output is agent-parseable
- [ ] Docs added to `documentation/`
- [ ] README.md tools table updated
- [ ] .env.example updated (if new env vars)
