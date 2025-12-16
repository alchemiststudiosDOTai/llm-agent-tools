# Architecture

Design principles and patterns for LLM agent tools.

## Core Philosophy

These tools exist in the space between "AI assistant" and "operating system". An agent using these tools should feel like a competent developer at a terminal - not fighting with the tools, not guessing at outputs, not surprised by behavior.

**Design for the agent's working memory.** Every token matters. Output should be information-dense but scannable. Error messages should be actionable, not just descriptive.

**Fail fast, fail loud.** Silent failures are catastrophic for agents. An agent that thinks an operation succeeded when it didn't will compound errors. Exit codes and stderr are not optional.

**Respect the Unix contract.** stdin/stdout/stderr exist for reasons. Don't mix concerns. Output goes to stdout. Errors go to stderr. Exit codes communicate success/failure.

## The Interface Contract

Every tool MUST:

```
1. Exit 0 on success, non-zero on failure
2. Send normal output to stdout
3. Send errors to stderr
4. Support -h/--help
5. Validate inputs before acting
6. Use set -euo pipefail
```

Every tool SHOULD:

```
1. Provide sensible defaults
2. Include usage examples in help
3. Support both short (-n) and long (--num) flags
4. Output structured formats (markdown/JSON)
5. Respect environment variables for config
6. Include version info
```

## Tool Categories

### 1. Read Tools (Information Retrieval)

Purpose: Fetch data from external sources.

Characteristics:
- Idempotent - running twice produces same result
- No side effects on external systems
- Support pagination/limits
- Return structured data

Examples: `exa-search.sh`, future `weather.sh`, `stock-price.sh`

Pattern:
```bash
# Read tools should:
# - Default to reasonable result limits
# - Support output format selection
# - Include metadata (cost, count, timing)

./tools/exa-search.sh -n 5 "query"           # Limited results
./tools/exa-search.sh -o json "query"        # Structured output
```

### 2. Write Tools (State Modification)

Purpose: Create, update, or delete resources.

Characteristics:
- NOT idempotent - running twice may have different effects
- Clear confirmation of what changed
- Support dry-run mode where applicable
- Require explicit confirmation for destructive ops

Examples: future `create-gist.sh`, `send-email.sh`, `deploy.sh`

Pattern:
```bash
# Write tools should:
# - Echo what was created/changed
# - Return identifiers for created resources
# - Support --dry-run for preview

./tools/create-gist.sh --dry-run file.txt    # Preview
./tools/create-gist.sh file.txt              # Returns gist URL
```

### 3. Transform Tools (Data Processing)

Purpose: Convert data between formats.

Characteristics:
- Pure functions - output depends only on input
- No network calls
- Fast execution
- Composable via pipes

Examples: future `json-to-csv.sh`, `format-markdown.sh`, `extract-urls.sh`

Pattern:
```bash
# Transform tools should:
# - Read from stdin or file argument
# - Write to stdout
# - Be pipeable

cat data.json | ./tools/json-to-csv.sh
./tools/json-to-csv.sh data.json
```

### 4. Query Tools (System Introspection)

Purpose: Inspect local system state.

Characteristics:
- Read-only
- Fast
- No external dependencies
- Useful for agent context-gathering

Examples: future `git-status.sh`, `disk-usage.sh`, `port-check.sh`

Pattern:
```bash
# Query tools should:
# - Run quickly
# - Return immediately actionable info
# - Format for quick scanning

./tools/git-status.sh                        # Clean summary
./tools/port-check.sh 3000 8080              # Check multiple ports
```

## Output Design

### When to Use Markdown

Default for human-agent hybrid consumption:
- Search results (titles, URLs, snippets)
- Status reports
- Multi-part responses
- Anything with prose

Markdown rules:
```
# Heading for context (what query/operation)
## Subheadings for sections

1. Numbered lists for ordered results
- Bullet lists for unordered info

> Blockquotes for excerpts/quotes

`inline code` for identifiers
```

### When to Use JSON

Use for:
- Programmatic processing
- Piping to other tools
- Preserving exact data types
- Complex nested structures

JSON rules:
```json
{
  "status": "success|error",
  "data": { ... },
  "metadata": {
    "count": 10,
    "cost": 0.001,
    "timing_ms": 234
  }
}
```

### Output Format Flag

Support `-o/--output` with at least:
- `markdown` (default) - human readable
- `json` - machine readable

Optional:
- `csv` - for tabular data
- `plain` - minimal formatting

## Error Handling

### Exit Codes

```
0   - Success
1   - General error (bad input, missing config)
2   - Usage error (bad arguments, --help triggered)
3   - Network error (API unreachable, timeout)
4   - Authentication error (bad API key, expired token)
5   - Resource error (not found, quota exceeded)
```

### Error Message Format

```bash
die() {
    echo "error: $*" >&2
    exit 1
}

# Good error messages:
die "EXA_API_KEY environment variable not set"
die "API returned 429: rate limit exceeded, retry after 60s"
die "invalid date format '$date', expected YYYY-MM-DD"

# Bad error messages:
die "failed"
die "error occurred"
die "invalid input"
```

### Validation Order

```bash
# 1. Check environment/config first
[[ -z "${API_KEY:-}" ]] && die "API_KEY not set"

# 2. Validate arguments
[[ -z "$query" ]] && usage
[[ "$num" -gt 100 ]] && die "num cannot exceed 100"

# 3. Check dependencies
command -v jq >/dev/null || die "jq is required but not installed"

# 4. Then proceed with operation
```

## Resource Management

### Built-in Limits

Every tool should have sensible defaults that prevent runaway operations:

```bash
# Default limits
num_results=10       # Not 1000
timeout=30           # Seconds, not infinite
max_retries=3        # Don't retry forever
```

### Pagination

For tools that return lists:

```bash
./tools/search.sh --offset 0 --limit 10 "query"   # Page 1
./tools/search.sh --offset 10 --limit 10 "query"  # Page 2
```

Output should include pagination metadata:
```markdown
---
Results: 10 of 347 | Page: 1 | Next: --offset 10
```

### Timeouts

```bash
# Use curl timeouts
curl --connect-timeout 5 --max-time 30 ...

# Or implement manually
timeout 30 long-running-command || die "operation timed out"
```

## Security

### API Keys

```bash
# Read from environment only
readonly API_KEY="${YOUR_API_KEY:-}"

# Never:
# - Hardcode keys
# - Accept keys as arguments (visible in process list)
# - Log keys
# - Include keys in error messages
```

### Input Sanitization

```bash
# Escape special characters for JSON payloads
query_escaped=$(printf '%s' "$query" | jq -Rs '.')

# Never interpolate user input into:
# - SQL queries
# - Shell commands (use arrays)
# - URL paths without encoding
```

### File Paths

```bash
# Validate paths stay within expected directories
realpath --relative-to="$ALLOWED_DIR" "$user_path" || die "path outside allowed directory"
```

## Testing

### Manual Testing Checklist

```bash
# Test help
./tools/your-tool.sh -h

# Test with no args (should show usage, exit 2)
./tools/your-tool.sh

# Test with valid input
./tools/your-tool.sh "test query"

# Test with missing env var
unset API_KEY && ./tools/your-tool.sh "test"

# Test error handling
./tools/your-tool.sh --invalid-flag
./tools/your-tool.sh ""
```

### What to Verify

```
[ ] Help text is complete and accurate
[ ] Exit codes are correct
[ ] Errors go to stderr
[ ] Output is parseable (valid markdown/JSON)
[ ] Handles network failures gracefully
[ ] Respects timeout limits
[ ] Produces consistent output format
```

## Performance Guidelines

### Response Time Targets

```
< 1s   - Local operations, cached data
< 5s   - Simple API calls
< 30s  - Complex searches, multiple API calls
> 30s  - Should show progress or be backgroundable
```

### Progress Indication

For long operations, emit to stderr:
```bash
echo "searching... (10/100)" >&2
```

### Caching

If implementing caching:
```bash
# Cache location
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/llm-tools"

# Cache key from inputs
cache_key=$(echo "$query $options" | md5sum | cut -d' ' -f1)

# Check cache before API call
if [[ -f "$CACHE_DIR/$cache_key" ]]; then
    cat "$CACHE_DIR/$cache_key"
    exit 0
fi
```

## Directory Structure

```
llm-agent-tools/
├── tools/                    # Executable scripts
│   ├── exa-search.sh
│   └── future-tool.sh
├── documentation/
│   ├── architecture.md       # This file
│   ├── creating-tools.md     # Contributor guide
│   ├── exa-search.md         # Per-tool docs
│   └── future-tool.md
├── .env.example              # Template for env vars
└── README.md                 # Project overview
```

## Naming Conventions

### Script Names

```
verb-noun.sh           # Action-oriented
exa-search.sh          # API name + action
git-summary.sh         # System + action

NOT:
search.sh              # Too generic
my-tool.sh             # Meaningless
searchTool.sh          # No camelCase
```

### Flag Names

```
-n, --num              # Short common abbreviation
-o, --output           # Standard for output format
-v, --verbose          # Universal verbose flag
-q, --quiet            # Suppress non-essential output
-h, --help             # Always present
--dry-run              # For write operations
```

### Environment Variables

```
SERVICE_API_KEY        # API key for SERVICE
TOOL_SETTING           # Config for specific tool

NOT:
apikey                 # Lowercase
API-KEY                # Hyphens
```

## Agent Integration Patterns

### Tool Discovery

Agents should be able to list available tools:
```bash
ls tools/*.sh | xargs -I{} basename {} .sh
```

### Dynamic Help

Agents can query any tool:
```bash
./tools/exa-search.sh --help 2>&1 | head -20
```

### Chaining Tools

Design for composition:
```bash
# Search, extract URLs, check which are live
./tools/exa-search.sh -o json "topic" | \
    jq -r '.results[].url' | \
    xargs -I{} ./tools/url-check.sh {}
```

### Error Recovery

Agents should handle common failures:
```bash
# Retry with backoff on rate limit
if ! ./tools/api-tool.sh "$query"; then
    sleep 5
    ./tools/api-tool.sh "$query"
fi
```

## Checklist for New Tools

Before adding a tool, verify:

```
Design:
[ ] Single clear purpose
[ ] Fits a category (read/write/transform/query)
[ ] Doesn't duplicate existing tool
[ ] Dependencies are minimal (curl, jq, coreutils)

Implementation:
[ ] set -euo pipefail
[ ] die() function
[ ] usage() function
[ ] -h/--help flag
[ ] Validates env vars early
[ ] Validates arguments
[ ] Proper exit codes

Output:
[ ] stdout for data
[ ] stderr for errors
[ ] Supports -o/--output format flag
[ ] Includes relevant metadata

Documentation:
[ ] Tool doc in documentation/
[ ] Added to README.md table
[ ] .env.example updated
[ ] Examples are tested
```
