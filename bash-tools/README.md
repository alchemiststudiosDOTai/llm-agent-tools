# Bash Tools for LLM Agents — Dead Code Discovery

Lightweight Bash utilities to find dead and unreachable code across Python and TypeScript/JavaScript, normalizing results into a single TSV your agents and CI can consume.

## Features
- AST-grep rules for obvious dead/unreachable blocks.
- Optional Vulture (Python) and ts-prune (TS/JS) integration.
- Unified TSV output: `tool\tpath\tline\tcode\tseverity\tmessage`.
- Works locally and in CI, with ignore filtering and thresholds.

## Quick Start
Requirements: `bash`, `ast-grep` (recommended), optionally `vulture` and/or `ts-prune` if present.

1) Install analyzers you want:
- ast-grep: https://ast-grep.github.io/
- vulture: `pip install vulture`
- ts-prune: `npm i -g ts-prune`

2) Run the orchestrator:
```bash
chmod +x deadcode.sh
./deadcode.sh .
```

Outputs are written to `.deadcode_out/`, with a merged `findings.tsv`.

## Usage
```bash
# Auto-detect languages
./deadcode.sh path/to/dir

# Force a language
LANG=python ./deadcode.sh src/
LANG=typescript ./deadcode.sh src/

# Set severity threshold for reporting
SEVERITY_MIN=warning ./deadcode.sh .

# Customize output directory and ignore file
OUT=.deadcode_out IGNORE_FILE=.deadcodeignore ./deadcode.sh .
```

## Output Schema (TSV)
File: `.deadcode_out/findings.tsv`
- Columns: `tool\tpath\tline\tcode\tseverity\tmessage`
- Tools: `ast-grep`, `vulture`, `ts-prune` (as available)
- Example:
```
ast-grep	src/foo.py	42	unreachable-after-return	warning	Unreachable code after return
vulture	src/util.py	10	UNUSED	info	unreferenced function 'helper'
ts-prune	src/lib.ts	-	UNUSED_EXPORT	info	Foo is unused
```

## Configuration
- `.deadcodeignore` (optional): lines are substrings to filter out from all tool outputs.
- `.deadcode.yml` (optional): enable/disable tools, set severity threshold, include/exclude globs, and point to rule files.
- Env vars:
  - `LANG=auto|python|typescript`
  - `OUT=.deadcode_out`
  - `IGNORE_FILE=.deadcodeignore`
  - `SEVERITY_MIN=info|warning|error`

### .deadcode.yml fields
- `severity_min`: Minimum severity to report (`info|warning|error`).
- `include`: List of glob patterns to include (in addition to defaults per language).
- `exclude`: List of glob patterns to exclude (e.g., `**/node_modules/**`).
- `tools.ast_grep.enabled`: `true|false`.
- `tools.ast_grep.rules_file.python`: Path to Python rules YAML.
- `tools.ast_grep.rules_file.typescript`: Path to TS/JS rules YAML.
- `tools.vulture.enabled`: `true|false` (Python unused code; optional).
- `tools.ts_prune.enabled`: `true|false` (TS unused exports; optional).

Note: Environment variables still work; config file values override defaults but can be overridden by explicitly setting env vars at runtime.

### Example .deadcode.yml
```yaml
severity_min: warning

include:
  - "src/**"

exclude:
  - "**/node_modules/**"
  - "**/dist/**"
  - "**/build/**"
  - "**/.venv/**"
  - "**/migrations/**"
  - "**/tests/**"

tools:
  ast_grep:
    enabled: true
    rules_file:
      python: deadcode.rules.py.yml
      typescript: deadcode.rules.ts.yml
  vulture:
    enabled: true
    extra_args: []
  ts_prune:
    enabled: true
    extra_args: ["-s", "-i", "node_modules"]
```

## AST-grep Rules
- Python rules: `deadcode.rules.py.yml`
- TypeScript/JS rules: `deadcode.rules.ts.yml`
Messages embed `[code=...]` and `[sev=...]` so the orchestrator can fill the TSV columns consistently.

## CI Example (GitHub Actions)
```yaml
name: Dead Code
on: [pull_request]
jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install ast-grep
        run: |
          curl -fsSL https://ast-grep.github.io/install.sh | bash -s -- -y
          echo "$HOME/.cargo/bin" >> $GITHUB_PATH
      - name: Optional analyzers
        run: |
          pipx install vulture || true
          npm i -g ts-prune || true
      - name: Dead code scan
        run: |
          chmod +x deadcode.sh
          ./deadcode.sh . || echo "dead code found"
      - name: Upload results
        uses: actions/upload-artifact@v4
        with:
          name: deadcode-tsv
          path: .deadcode_out/findings.tsv
```

## Exit Codes
- `0`: ran and no findings at/above threshold.
- `1`: findings present at/above threshold.
- `2`: misconfiguration or no supported languages/tools ran.

## Notes & Limits
- AST-grep is syntax-based; pair with language tools for unused symbols.
- If optional tools are missing, they’re skipped with a notice.
- Honors `.git` ignore by virtue of your invocation paths; add your own globs if needed.

## Roadmap
- `.deadcode.yml` config support, JSON output option, parallelization, and richer rule packs.
