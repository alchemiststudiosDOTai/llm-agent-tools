# verify-tools.sh

Validate tool compliance with project standards. Tests help output, JSON validity, and shellcheck analysis.

Useful for CI pipelines, onboarding verification, and quality assurance.

## Quick Start

```bash
# Verify all tools
./tools/verify-tools.sh

# Skip shellcheck for faster results
./tools/verify-tools.sh --skip-shellcheck
```

## Options

```
-o, --output <FMT>    Output format: markdown, json (default: markdown)
-v, --verbose         Show detailed test output
--skip-shellcheck     Skip shellcheck analysis
-h, --help            Show help
```

## Arguments

```
[TOOL...]             Specific tools to verify (default: all in tools/)
```

## Examples

### Full Verification

```bash
./tools/verify-tools.sh
```

Output:
```markdown
# Tool Verification Report

## Summary
- Total tests: 12
- Passed: 10
- Failed: 0
- Skipped: 2

## Results

| Tool | Help | JSON | Shellcheck | Status |
|------|------|------|------------|--------|
| `exa-search.sh` | PASS | SKIP | PASS | OK |
| `memory-journal.sh` | PASS | PASS | PASS | OK |
| `scratchpad.sh` | PASS | PASS | PASS | OK |

---
Verified at: 2025-12-20T10:40:00-06:00
```

### JSON Output

```bash
./tools/verify-tools.sh -o json
```

Output:
```json
{
  "summary": {
    "total_tests": 12,
    "passed": 10,
    "failed": 0,
    "skipped": 2
  },
  "tools": [...],
  "timestamp": "2025-12-20T10:40:00-06:00"
}
```

### Verify Specific Tool

```bash
./tools/verify-tools.sh scratchpad.sh
```

### Verbose Mode

```bash
./tools/verify-tools.sh -v
```

Shows detailed output for each test as it runs.

## Tests Performed

### Help Test
- Runs `tool -h` and verifies output contains USAGE/OPTIONS/COMMANDS
- Ensures tools are self-documenting

### JSON Test
- Runs tool with `-o json` and a safe read-only command
- Validates output is parseable JSON via `jq`
- Skipped for tools requiring API keys (exa-search.sh)

### Shellcheck Test
- Runs `shellcheck` static analysis
- Reports warnings and errors
- Gracefully skips if shellcheck not installed

## Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

## CI Usage

```bash
# In CI pipeline
./tools/verify-tools.sh || exit 1

# Or with JSON for parsing
result=$(./tools/verify-tools.sh -o json)
if [[ $(echo "$result" | jq '.summary.failed') -gt 0 ]]; then
    exit 1
fi
```

## Dependencies

- `jq`
- `shellcheck` (optional, gracefully skipped if missing)
