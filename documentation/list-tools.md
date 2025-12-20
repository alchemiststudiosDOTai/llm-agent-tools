# list-tools.sh

Discover available LLM agent tools. Lists all tools with their descriptions and versions.

Designed for agents to programmatically discover available capabilities without prior knowledge of the toolset.

## Quick Start

```bash
# List all tools
./tools/list-tools.sh

# List as JSON for programmatic use
./tools/list-tools.sh -o json
```

## Options

```
-o, --output <FMT>    Output format: markdown, json (default: markdown)
-v, --verbose         Show full tool descriptions
-h, --help            Show help
```

## Examples

### Basic Listing

```bash
./tools/list-tools.sh
```

Output:
```markdown
# Available Tools

| Tool | Version | Description |
|------|---------|-------------|
| `exa-search.sh` | 1.0.0 | Exa API search tool for LLM agents |
| `memory-journal.sh` | 2.0.0 | Project context and decision logging |
| `scratchpad.sh` | 2.0.0 | External memory for LLM agent reasoning |

Run `./tools/<tool> -h` for detailed usage.
```

### JSON Output

```bash
./tools/list-tools.sh -o json
```

Output:
```json
{
  "tools": [
    {
      "name": "exa-search.sh",
      "path": "./tools/exa-search.sh",
      "version": "1.0.0",
      "description": "Exa API search tool for LLM agents"
    }
  ],
  "count": 3
}
```

### Verbose Mode

```bash
./tools/list-tools.sh -v
```

Shows full descriptions extracted from tool header comments.

## Agent Usage

Agents can use this tool to discover capabilities:

```bash
# Get available tools as JSON
tools=$(./tools/list-tools.sh -o json)

# Extract tool names
echo "$tools" | jq -r '.tools[].name'

# Find a specific capability
echo "$tools" | jq -r '.tools[] | select(.description | contains("search"))'
```

## Dependencies

- `jq`
