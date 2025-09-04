#!/usr/bin/env bash
set -euo pipefail

# deadcode.sh — orchestrates static analyzers and normalizes to TSV
# Output schema (TSV): tool	path	line	code	severity	message

TARGET="${1:-.}"
OUT_DIR="${OUT:-.deadcode_out}"
IGNORE_FILE="${IGNORE_FILE:-.deadcodeignore}"
CONFIG_FILE="${CONFIG:-.deadcode.yml}"
LANG_SEL="${LANG:-auto}"   # auto | python | typescript
SEVERITY_MIN="${SEVERITY_MIN:-info}" # info|warning|error
CFG_AST_GREP_ENABLED=1
CFG_VULTURE_ENABLED=1
CFG_TSPRUNE_ENABLED=1
CFG_RULES_PY="deadcode.rules.py.yml"
CFG_RULES_TS="deadcode.rules.ts.yml"
declare -a CFG_INCLUDE_GLOBS=()
declare -a CFG_EXCLUDE_GLOBS=()

mkdir -p "$OUT_DIR"
FINDINGS_TSV="$OUT_DIR/findings.tsv"
TMP_DIR="$OUT_DIR/.tmp"
mkdir -p "$TMP_DIR"
> "$FINDINGS_TSV"

severity_rank() {
  case "$1" in
    error) echo 3 ;;
    warning) echo 2 ;;
    info|*) echo 1 ;;
  esac
}

SEV_MIN_RANK=$(severity_rank "$SEVERITY_MIN")

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# Minimal YAML loader to flatten keys into dot-paths and capture simple lists
load_config() {
  [[ -f "$CONFIG_FILE" ]] || return 0
  local line
  # Flatten YAML into key paths
  awk '
    function ltrim(s){sub(/^\s+/,"",s);return s}
    function rtrim(s){sub(/\s+$/,"",s);return s}
    function trim(s){return rtrim(ltrim(s))}
    function depth(spaces){ return int(length(spaces)/2) }
    BEGIN{ FS=":" }
    {
      # strip comments
      sub(/#.*/, "")
      if ($0 ~ /^\s*$/) next
      match($0, /^( * )/, m)
      d=depth(m[1])
      rest=$0
      gsub(/^ +/, "", rest)
      if (rest ~ /^- /) {
        item=rest
        sub(/^- +/, "", item)
        gsub(/^"|"$/, "", item)
        # last key in stack is the list name
        if (stack_depth>0) {
          key=stack[stack_depth]
          print key"[]="item
        }
        next
      }
      # key: value or key:
      split($0, parts, ":")
      key=parts[1]; gsub(/^ +| +$/, "", key)
      val=$0; sub(/^[^:]*:/, "", val); val=trim(val)
      # adjust stack to depth d
      while (stack_depth>d) { delete stack[stack_depth]; stack_depth-- }
      if (val == "") {
        stack_depth++
        stack[stack_depth]=(stack_depth>1?stack[stack_depth-1]"."key:key)
      } else {
        full=(stack_depth>0?stack[stack_depth]"."key:key)
        gsub(/^"|"$/, "", val)
        print full"="val
      }
    }
  ' "$CONFIG_FILE" | while IFS= read -r kv; do
    [[ -z "$kv" ]] && continue
    if [[ "$kv" =~ ^severity_min=(.*)$ ]]; then SEVERITY_MIN="${BASH_REMATCH[1]}"; fi
    if [[ "$kv" =~ ^include\[\]=(.+)$ ]]; then CFG_INCLUDE_GLOBS+=("${BASH_REMATCH[1]}"); fi
    if [[ "$kv" =~ ^exclude\[\]=(.+)$ ]]; then CFG_EXCLUDE_GLOBS+=("${BASH_REMATCH[1]}"); fi
    if [[ "$kv" =~ ^tools\.ast_grep\.enabled=(.*)$ ]]; then [[ "${BASH_REMATCH[1]}" =~ ^(false|0|no)$ ]] && CFG_AST_GREP_ENABLED=0; fi
    if [[ "$kv" =~ ^tools\.vulture\.enabled=(.*)$ ]]; then [[ "${BASH_REMATCH[1]}" =~ ^(false|0|no)$ ]] && CFG_VULTURE_ENABLED=0; fi
    if [[ "$kv" =~ ^tools\.ts_prune\.enabled=(.*)$ ]]; then [[ "${BASH_REMATCH[1]}" =~ ^(false|0|no)$ ]] && CFG_TSPRUNE_ENABLED=0; fi
    if [[ "$kv" =~ ^tools\.ast_grep\.rules_file\.python=(.*)$ ]]; then CFG_RULES_PY="${BASH_REMATCH[1]}"; fi
    if [[ "$kv" =~ ^tools\.ast_grep\.rules_file\.typescript=(.*)$ ]]; then CFG_RULES_TS="${BASH_REMATCH[1]}"; fi
  done
}

detect_langs() {
  local want_python=0 want_ts=0
  if [[ "$LANG_SEL" == "python" ]]; then want_python=1; fi
  if [[ "$LANG_SEL" == "typescript" ]]; then want_ts=1; fi
  if [[ "$LANG_SEL" == "auto" ]]; then
    if has_cmd rg; then
      rg --hidden --glob '!.git' -l '\.py$' "$TARGET" >/dev/null 2>&1 && want_python=1 || true
      rg --hidden --glob '!.git' -l '\.(ts|tsx|js|jsx)$' "$TARGET" >/dev/null 2>&1 && want_ts=1 || true
    else
      find "$TARGET" -type f -name '*.py' | read || true && want_python=1
      find "$TARGET" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \) | read || true && want_ts=1
    fi
  fi
  echo "$want_python $want_ts"
}

list_files_for_lang() {
  local lang="$1"
  local rg_args=(--hidden --glob '!.git' --files)
  local base="$TARGET"
  # include default language globs
  if [[ "$lang" == "python" ]]; then
    rg_args+=(--glob '**/*.py')
  else
    rg_args+=(--glob '**/*.ts' --glob '**/*.tsx' --glob '**/*.js' --glob '**/*.jsx')
  fi
  # apply config include globs
  for g in "${CFG_INCLUDE_GLOBS[@]:-}"; do rg_args+=(--glob "$g"); done
  # apply config excludes
  for g in "${CFG_EXCLUDE_GLOBS[@]:-}"; do rg_args+=(--glob "!$g"); done
  if has_cmd rg; then
    rg "" "$base" "${rg_args[@]}" 2>/dev/null || true
  else
    # Fallback: find then filter roughly by extension only
    if [[ "$lang" == "python" ]]; then
      find "$base" -type f -name '*.py' || true
    else
      find "$base" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \) || true
    fi
  fi
}

filter_ignores() {
  # stdin lines -> stdout lines with substrings removed per IGNORE_FILE
  if [[ -f "$IGNORE_FILE" ]]; then
    local tmpIn tmpOut
    tmpIn=$(mktemp)
    cat - > "$tmpIn"
    while IFS= read -r pat; do
      [[ -z "$pat" || "$pat" =~ ^# ]] && continue
      tmpOut=$(mktemp)
      grep -Fv -- "$pat" "$tmpIn" > "$tmpOut" || true
      mv "$tmpOut" "$tmpIn"
    done < "$IGNORE_FILE"
    cat "$tmpIn"
    rm -f "$tmpIn"
  else
    cat -
  fi
}

append_tsv() {
  # args: tool path line code severity message
  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$1" "$2" "$3" "$4" "$5" "$6" >> "$FINDINGS_TSV"
}

run_ast_grep() {
  local lang="$1"; shift
  local rules_file="$1"; shift
  [[ -f "$rules_file" ]] || return 0
  if ! has_cmd ast-grep; then
    echo "[warn] ast-grep not found; skipping ${lang}" >&2
    return 0
  fi
  local raw="$OUT_DIR/astgrep.${lang}.txt"
  mapfile -t files < <(list_files_for_lang "$lang")
  if [[ ${#files[@]} -eq 0 ]]; then return 0; fi
  ast-grep --no-color --config "$rules_file" "${files[@]}" > "$raw" 2>/dev/null || true
  filter_ignores < "$raw" | while IFS= read -r line; do
    # Expect format: path:line: [code=...][sev=...] message
    # Fallbacks if not matching.
    [[ -z "$line" ]] && continue
    local path linen msg code sev
    path="-"; linen="-"; code="-"; sev="warning"; msg="$line"
    if [[ "$line" =~ ^([^:]+):([0-9]+):[[:space:]]*(.*)$ ]]; then
      path="${BASH_REMATCH[1]}"; linen="${BASH_REMATCH[2]}"; msg="${BASH_REMATCH[3]}"
    fi
    if [[ "$msg" =~ \[code=([^\]]+)\]\[sev=([^\]]+)\][[:space:]]*(.*)$ ]]; then
      code="${BASH_REMATCH[1]}"; sev="${BASH_REMATCH[2]}"; msg="${BASH_REMATCH[3]}"
    fi
    # Severity threshold
    if (( $(severity_rank "$sev") >= SEV_MIN_RANK )); then
      append_tsv "ast-grep" "$path" "$linen" "$code" "$sev" "$msg"
    fi
  done
}

run_vulture() {
  # Python unused-code finder
  has_cmd vulture || { echo "[info] vulture not found; skipping" >&2; return 0; }
  local raw="$OUT_DIR/vulture.txt"
  mapfile -t files < <(list_files_for_lang python)
  if [[ ${#files[@]} -eq 0 ]]; then return 0; fi
  vulture "${files[@]}" > "$raw" 2>/dev/null || true
  filter_ignores < "$raw" | while IFS= read -r line; do
    # vulture format: path:line: message
    [[ -z "$line" ]] && continue
    local path linen msg
    path="-"; linen="-"; msg="$line"
    if [[ "$line" =~ ^([^:]+):([0-9]+):[[:space:]]*(.*)$ ]]; then
      path="${BASH_REMATCH[1]}"; linen="${BASH_REMATCH[2]}"; msg="${BASH_REMATCH[3]}"
    fi
    append_tsv "vulture" "$path" "$linen" "UNUSED" "info" "$msg"
  done
}

run_ts_prune() {
  # TS/JS unused export finder
  has_cmd ts-prune || { echo "[info] ts-prune not found; skipping" >&2; return 0; }
  local raw="$OUT_DIR/ts-prune.txt"
  # ts-prune works best at project root with tsconfig; include/exclude is not fully applied
  ts-prune -s -i node_modules "$TARGET" > "$raw" 2>/dev/null || true
  filter_ignores < "$raw" | while IFS= read -r line; do
    # typical ts-prune line: path: exportName
    [[ -z "$line" ]] && continue
    local path rest
    path="${line%%:*}"
    rest="${line#*: }"
    append_tsv "ts-prune" "$path" "-" "UNUSED_EXPORT" "info" "${rest} is unused"
  done
}

main() {
  load_config
  local want_python want_ts
  read -r want_python want_ts < <(detect_langs)
  local ran_any=0

  if [[ "$want_python" == "1" ]]; then
    ran_any=1
    if [[ "$CFG_AST_GREP_ENABLED" -eq 1 ]]; then run_ast_grep "python" "$CFG_RULES_PY"; fi
    if [[ "$CFG_VULTURE_ENABLED" -eq 1 ]]; then run_vulture; fi
  fi
  if [[ "$want_ts" == "1" ]]; then
    ran_any=1
    if [[ "$CFG_AST_GREP_ENABLED" -eq 1 ]]; then run_ast_grep "typescript" "$CFG_RULES_TS"; fi
    if [[ "$CFG_TSPRUNE_ENABLED" -eq 1 ]]; then run_ts_prune; fi
  fi

  if [[ "$ran_any" == "0" ]]; then
    echo "No supported languages detected (or LANG set to unsupported)." >&2
    exit 2
  fi

  # Summarize
  local count
  count=$(wc -l < "$FINDINGS_TSV" | tr -d ' ' || echo 0)
  echo "Deadcode findings: $count"
  echo "TSV: $FINDINGS_TSV (tool\tpath\tline\tcode\tseverity\tmessage)"

  # Exit code based on threshold
  if [[ "$count" -gt 0 && "$SEVERITY_MIN" != "error-only" ]]; then
    exit 1
  fi
}

main "$@"
