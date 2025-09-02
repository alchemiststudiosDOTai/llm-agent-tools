# Research – delta_date_fix
**Date:** 2025-09-01 22:25:02  
**Owner:** user  
**Phase:** Research (RAG + Search + Manual Review)

## Goal
Summarize all *existing knowledge* before any new work.

## Inputs
- RAG Queries:  
  - `./claude-rag-lite.sh query "<term>"`
- Additional Search:  
  - `grep -ri "<term>" .claude/`

## Findings
- Relevant files & why they matter:
  - `<file>` → `<reason>`
  - `<file>` → `<reason>`

## Key Patterns / Solutions Found
- `<pattern>`: short description, relevance

## Knowledge Gaps
- Missing context or details for next phase

## References
- Links or filenames for full review

## Goal
Ensure dates in delta logs are concrete timestamps, not shell placeholders.

## Findings
- Cause: Here-doc used single quotes, preventing `$(date ...)` expansion.
- Scope: Only affects delta log we wrote; templates already substitute `{{date}}`.
- Options: Fix instance now; optionally add a helper or guideline to avoid single-quoted heredocs when inserting dynamic values.

## Knowledge Gaps
- Do we want time-of-day in scaffolded files, not just date?

## References
- `.claude/delta/rag_db_rebuild_*.md`
