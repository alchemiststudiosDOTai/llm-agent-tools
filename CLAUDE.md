# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Bash tools for LLM agents. No MCP, no orchestration layers - just shell scripts that agents invoke directly via CLI.

## Running Tools

```bash
# Set up environment
source .env

# Run a tool
./tools/exa-search.sh "query"
./tools/exa-search.sh -o json "query"   # JSON output
./tools/exa-search.sh -h                 # Help for any tool
```

## Architecture

**Directory structure:**
- `tools/` - Executable bash scripts
- `documentation/` - Per-tool docs and architecture guide

**Tool categories:**
- Read tools (API queries, searches) - idempotent, no side effects
- Write tools (create/modify resources) - support `--dry-run`
- Transform tools (data conversion) - pure, pipeable
- Query tools (local system info) - fast, no deps

## Creating New Tools

Every tool must follow `documentation/creating-tools.md` template:

```bash
#!/usr/bin/env bash
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
usage() { cat >&2 <<EOF ... EOF; exit 1; }

# Validate env vars first, then args
[[ -z "${API_KEY:-}" ]] && die "API_KEY not set"
```

**Requirements:**
- `set -euo pipefail` at top
- **MUST include `-h/--help` flag** - This is critical. Other agents may use weaker models that need to discover how to use tools. The help output must include usage, commands/options, and examples.
- Output to stdout, errors to stderr
- Exit 0 on success, non-zero on failure
- Support `-o json` for structured output

**After creating a tool:**
1. Add docs to `documentation/<tool-name>.md`
2. Update tools table in `README.md`
3. Add env vars to `.env.example`

## Dependencies

Tools should only require: `curl`, `jq`, standard coreutils

## Using Tools

**All tools support `-h/--help`.** Run this first to learn how to use any tool:

```bash
./tools/scratchpad.sh -h
./tools/exa-search.sh -h
```

This is the primary way to discover commands, options, and examples. Tools are self-documenting.



