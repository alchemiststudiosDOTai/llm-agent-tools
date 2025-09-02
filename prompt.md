### Instruction

Your task is to act as a **Repo optimizer for an ongoing project**. You MUST set a **baseline today** and make the repo **Claude/LLM-friendly** going forward. You MUST be idempotent: if targets already exist, **read/merge/update**—**no duplicates**. You MUST operate autonomously: **Do not ask questions.** Gather all context from the repo and GitHub using `git` and `gh`.

You MUST enforce the **exact** `.claude/` categories (the scratchpad validates these names):
`.claude/{metadata,code_index,debug_history,patterns,cheatsheets,qa,delta}` and manage `./.claude/anchors.json`. Do not invent categories.

You MUST automatically crawl (no user prompts):

* **Churn & tags:** `git log`, `git tag --sort=creatordate`, `git diff <prev> <curr>`
* **PRs/issues:** `gh pr list --state merged`, `gh pr view <num> --json ...`, `gh issue list --state closed`
* **Releases:** `gh release list`
* **File intro SHAs:** `git log --diff-filter=A -1 --format=%H -- <path>`

You MUST:

* Detect existing `.claude/*` files/dirs and **merge** rather than overwrite.
* Use **today’s date** for the baseline filename; if it exists, **update** its sets.
* Generate anchor IDs: `sha1(path + symbol + first_seen_file_sha)`; fall back to **file-scope** anchors when symbol history is hard.
* Limit backfill to **last 3–6 months** or **since last tag/release** (whichever is **shorter**).
* Favor **top-churn** components for first anchors.
* Keep outputs **short, structured, diff-friendly** (YAML/JSON).
* Ensure your answer is unbiased and avoids relying on stereotypes.
* **Never** duplicate files, rewrite large docs, or add unrelated content.
* **You will be penalized** for duplication, verbose narration, destructive rewrites, or ignoring `gh`/`git` evidence.
* Answer a question given in a natural, human-like manner.

Repository organization rules (for generic KB content already in the repo):

* Error fixes → `.claude/debug_history/`
* How-tos → `.claude/patterns/` or `.claude/cheatsheets/`
* Q\&As → `.claude/qa/`
* Architecture docs → `.claude/metadata/`
* Code mappings → `.claude/code_index/`
  Implement non-destructive classification via **symlinks** under the above dirs to avoid duplication; only move files if clearly safe.

---

### Outputs (in this exact order)

1. **Plan (≤12 bullets)** — concrete steps you will execute, referencing the commands you’ll run.

2. **Idempotent Creator Script** — one **Python** file that:

   * Creates missing dirs only: `.claude/{metadata,code_index,debug_history,patterns,cheatsheets,qa,delta}`.
   * Runs `git`/`gh` via `subprocess` to gather:

     * churn → write `.claude/metadata/hotspots.txt`
     * tags/releases/PRs → select recent window (≤ last tag/release or 3–6 months, whichever shorter)
     * fixes → seed QA entries (from merged PRs and commits containing `fix|bug|hotfix`)
   * Builds/merges (load→merge→write, never blind overwrite):

     * `.claude/metadata/components.yml` (preserve existing keys; add missing)
     * `.claude/anchors.json` (merge, add new, mark **tombstone** when a previously anchored file disappears)
     * `.claude/delta/YYYY-MM-DD-baseline.yml` (create or update for **today**)
     * Raw diffs for last two tags in `.claude/delta/<prev>_to_<curr>.diff` **if absent**
   * Classifies existing KB docs into the 8 categories above by creating **symlinks** inside `.claude/*` (error fixes, how-tos, Q\&A, architecture, code mappings); no duplication.

3. **Files to Create/Update** — exact minimal templates/snippets, each in its own fenced block:

   * `./.claude/README.md` (if missing): one-screen directory overview.
   * `./.claude/metadata/components.yml` (merge example).
   * `./.claude/anchors.json` (schema + 2 sample entries).
   * `./.claude/delta/YYYY-MM-DD-baseline.yml` (use the template shape below).
   * `./.claude/qa/EXAMPLE.yml` (one seed entry tied to an anchor).

4. **Next PR Rules (5 bullets)** — contributor rules to keep the system current.

---

### Baseline Templates (use these shapes exactly)

`./.claude/delta/YYYY-MM-DD-baseline.yml`

```yaml
version: 1
date: YYYY-MM-DD
scope: baseline
apis:
  - component: <name>
    public_symbols: [<AnchorID>, ...]
risks:
  - area: <component-or-file>
    notes: "<1–2 lines>"
migration_notes: []
```

`./.claude/anchors.json` (schema)

```json
{
  "version": 1,
  "anchors": [
    {
      "id": "<sha1>",
      "path": "src/module/file.py",
      "kind": "function|class|file",
      "symbol": "name-or-null",
      "since": "<git_sha_first_seen_for_file>",
      "status": "active|tombstone"
    }
  ]
}
```

`./.claude/qa/EXAMPLE.yml`

```yaml
id: qa-<short-id>
anchors: ["<AnchorID>", "..."]
problem: "<error signature>"
cause: "<root cause>"
fix: "<commit or PR #>"
notes: "<1–2 lines>"
```

---

### Operating Constraints

* Use `gh` for GitHub data; degrade gracefully if missing by using local `git` only.
* If today’s baseline exists, **merge** into it; no new file.
* Keep every file under \~200 lines on first pass; link out rather than inlining long content.
* Use delimiters and output primers. Think step by step. Combine few-shot with concise reasoning where beneficial.
* You will be penalized for violating any constraints above.

---

### Output Primer

Plan:

1. …
2. …
3. …

(Idempotent Creator Script next, then **Files to Create/Update**, then **Next PR Rules**.)

---

### Example

**Context (delimiter):**

```
Repo: current working directory on main
Goal: establish .claude/ baseline and anchors from last 90 days or since last release (shorter)
```

**Use this prompt exactly as-is**
