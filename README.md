# LLM Agent Tools

Direct bash tools for LLM agents. No MCP, no orchestration layers, no vendor lock-in.

## Philosophy

Skip the complexity. Bash scripts work everywhere, live in git, and print every token to your terminal. Agents call these tools via CLI just like any other command.

Why bash over MCP:
- **Ubiquitous** - runs on any POSIX system
- **Transparent** - full visibility into every operation
- **Debuggable** - grep, diff, version control
- **Composable** - pipe output between tools

## Tools

| Tool | Description |
|------|-------------|
| `tools/exa-search.sh` | Web search via Exa API |
| `tools/memory-journal.sh` | Project context and decision logging |
| `tools/scratchpad.sh` | External memory for reasoning ([paper](https://arxiv.org/abs/2507.17699)) |
| `tools/list-tools.sh` | Discover available tools |
| `tools/verify-tools.sh` | Validate tool compliance |

## Setup

```bash
cp .env.example .env
# Add your API keys to .env

source .env
./tools/exa-search.sh "your query"
```

## For Agents

These tools are designed for LLM agents to invoke directly:

```bash
# Agent searches the web
./tools/exa-search.sh -n 5 "rust error handling best practices"

# Agent uses scratchpad for multi-step reasoning
./tools/scratchpad.sh set '{"peg_A": [3,2,1], "peg_B": [], "peg_C": []}'
./tools/scratchpad.sh pop peg_A && ./tools/scratchpad.sh push peg_C 1
./tools/scratchpad.sh get  # Check state
```

Output goes to stdout (for the agent), errors to stderr (for debugging).

## Adding New Tools

Add new scripts to `tools/`. Each tool should:
1. Use `set -euo pipefail`
2. Read config from environment variables
3. Output clean, parseable text to stdout
4. Send errors to stderr
5. Include `-h/--help`
6. Exit non-zero on failure
