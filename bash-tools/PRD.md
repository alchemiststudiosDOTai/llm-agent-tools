**Product Requirements Document (PRD)**

**Product**
- Bash Tools for LLM Agents (dead code discovery + unified findings export)

**Overview**
- Provide lightweight Bash utilities that orchestrate language-aware static analyzers to detect dead code and unreachable blocks across multi-language repos, then emit a single, machine-readable TSV feed that agentic systems can consume.

**Goals**
- Detect obvious dead code quickly with minimal setup.
- Support Python and TypeScript/JavaScript first; be extensible to others.
- Normalize findings from multiple tools into a single TSV schema.
- Work locally and in CI with predictable exit codes and performance.
- Allow simple configuration, filtering, and ignore controls.

**Non-Goals**
- Full dataflow analysis or type-checking beyond delegated tools.
- Refactoring or code modification; tools report only (auto-fix optional later).
- Managing project dependencies or language runtime installation.

**Primary Users**
- Engineers and LLM agents needing a compact, uniform stream of code-quality findings to prioritize cleanup and automate safe edits.

**Key Use Cases**
- Run in CI to fail PRs with newly introduced dead code.
- Run locally to generate a TSV for an agent to propose deletions.
- Periodic repo audits to measure and reduce dead code over time.

**Functional Requirements**
- CLI entry: `deadcode.sh [PATH]`
  - Detect languages present; or allow explicit `LANG=python|typescript|auto`.
  - Invoke supported analyzers per language and aggregate results.
- Supported analyzers (initial):
  - Python: `ast-grep` rules for unreachable and constant-guarded blocks; `vulture` for unused code (optional if installed).
  - TS/JS: `ast-grep` rules; `ts-prune` for unused exports (optional if installed).
- Output
  - Default output directory: `.deadcode_out/`.
  - Unified TSV file: `.deadcode_out/findings.tsv` with columns: `tool<TAB>path<TAB>line<TAB>code<TAB>severity<TAB>message`.
  - Write per-tool raw outputs for debugging (e.g., `astgrep.python.txt`).
- Configuration
  - Optional `.deadcodeignore`: line-based substrings to filter out matches.
  - Optional `.deadcode.yml`: toggles per-tool, severity thresholds, extra arguments, and path globs include/exclude.
  - Environment overrides: `LANG`, `OUT`, `IGNORE_FILE`, `CONFIG`.
- Exit codes
  - `0` on success with no findings above threshold.
  - `1` when findings >= threshold (e.g., severity warning+).
  - `2` for misconfiguration or missing required dependencies.
- Performance
  - Process only tracked/source files by default (configurable globs).
  - Parallelize per-language or per-path where safe (optional/phase 2).
- CI Integration
  - Print a summary to stdout and path to TSV artifacts.
  - Provide GitHub Actions snippet in docs.

**Non-Functional Requirements**
- Minimal external dependencies; degrade gracefully when optional tools are absent.
- Deterministic output formatting; stable across runs for the same input.
- Fast startup and sub-minute runtime on medium repos (<1000 files) with defaults.

**Data Model (TSV Schema)**
- Columns (tab-separated):
  - `tool`: identifier of source tool (e.g., `ast-grep`, `vulture`, `ts-prune`).
  - `path`: repo-relative file path.
  - `line`: 1-based line number or `-` when not applicable.
  - `code`: short rule or finding code (e.g., `if-false-dead`, `UNUSED_EXPORT`).
  - `severity`: `info|warning|error`.
  - `message`: concise human-readable description.

**Initial Rule Coverage (AST-grep)**
- Python: dead `if False`, `while False`; unreachable after `return|raise|break|continue`; post `sys.exit(...)`.
- TS/JS: dead `if (false)`, `while (false)`; unreachable after `return|throw|break|continue`; post `process.exit(...)`.

**CLI UX**
- `deadcode.sh .` → auto-detect languages; write `.deadcode_out/findings.tsv`; print counts per tool and overall.
- Flags/env:
  - `LANG=python|typescript|auto`
  - `OUT=.deadcode_out` `IGNORE_FILE=.deadcodeignore` `CONFIG=.deadcode.yml`
  - `SEVERITY_MIN=warning` (filter threshold)
  - `INCLUDE_GLOBS="src/**/*.py" EXCLUDE_GLOBS="**/tests/**"`

**Configuration Examples**
- `.deadcode.yml` keys:
  - `tools.ast_grep.enabled: true`
  - `tools.vulture.enabled: false`
  - `severity_min: warning`
  - `include: ["src/**"]`
  - `exclude: ["**/migrations/**", "**/tests/**"]`
  - `ast_grep.rules_file.python: deadcode.rules.py.yml`
  - `ast_grep.rules_file.typescript: deadcode.rules.ts.yml`

**Error Handling**
- Missing tool: emit clear stderr guidance; continue with available tools; set exit code `2` only if no tools ran.
- Malformed config: show line/field; fall back to sane defaults.
- Empty or huge outputs: truncate summary, keep full TSV artifact.

**Security/Privacy**
- Do not upload or transmit code; local-only analysis.
- Avoid reading files outside repo root; honor `.gitignore` by default (configurable).

**Success Metrics**
- Time-to-first-results < 30 seconds on a typical repo.
- Unified TSV consumed by downstream agent successfully (integration tested).
- Reduction in dead-code warnings over time in CI.

**Milestones**
- M0: Single-language (Python) via `ast-grep`; TSV normalization; ignore file.
- M1: Add TS/JS support; optional `vulture` and `ts-prune` integration.
- M2: Config file and severity threshold; CI samples and docs.
- M3: Parallelization and performance tuning; richer rule packs.

**Open Questions**
- Should we include ESLint for `no-unused-vars` by default when present?
- How should we map tool-native severities to our canonical levels?
- Do we want an optional JSON output alongside TSV?

**Deliverables**
- `deadcode.sh` orchestrator (Bash), rule packs `deadcode.rules.py.yml`, `deadcode.rules.ts.yml`, sample `.deadcode.yml`, and docs in `README.md`.
