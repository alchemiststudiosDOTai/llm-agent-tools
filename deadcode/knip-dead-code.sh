#!/usr/bin/env bash

set -euo pipefail

# Dead code analysis for TS/JS projects using Knip with contextual heuristics.

KNIP_CMD=${KNIP_CMD:-"npx knip"}
KNIP_ARGS=${KNIP_ARGS:-""}
KNIP_CONFIG=${KNIP_CONFIG:-""}
SRC_DIR=${SRC_DIR:-"./src"}
VERBOSE=${VERBOSE:-0}
TEST_PATTERNS=${TEST_PATTERNS:-"__tests__|\\.spec\\.|\\.test\\.|tests/|test/"}
FIELD_SEP=$'\x1f'

# Color setup (disabled when stdout is not a terminal).
if [ -t 1 ]; then
  BOLD='\033[1m'
  DIM='\033[2m'
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  MAGENTA='\033[0;35m'
  CYAN='\033[0;36m'
  RESET='\033[0m'
else
  BOLD=''
  DIM=''
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  MAGENTA=''
  CYAN=''
  RESET=''
fi

run_cmd() {
  if [ "$VERBOSE" -ge 1 ]; then
    echo -e "${DIM}    CMD: $*${RESET}" >&2
  fi
  eval "$@"
}

print_header() {
  echo ""
  echo -e "${BOLD}$1${RESET}"
  echo "$(echo "$1" | sed 's/./=/g')"
}

print_subheader() {
  echo ""
  echo -e "${BOLD}$1${RESET}"
  echo "$(echo "$1" | sed 's/./-/g')"
}

show_code_context() {
  local file=$1
  local line_num=$2
  local context_lines=${3:-2}

  if [ "$VERBOSE" -lt 2 ]; then
    return
  fi

  if [ -z "$file" ] || [ -z "$line_num" ]; then
    return
  fi

  if [ ! -f "$file" ]; then
    echo "  [Context unavailable: file not found]" >&2
    return
  fi

  if ! [[ "$line_num" =~ ^[0-9]+$ ]]; then
    return
  fi

  echo ""
  echo -e "${CYAN}Code Context:${RESET}"

  local start_line=$((line_num - context_lines))
  [ "$start_line" -lt 1 ] && start_line=1
  local end_line=$((line_num + context_lines))
  local total_lines
  total_lines=$(wc -l < "$file" | tr -d ' ')
  [ "$end_line" -gt "$total_lines" ] && end_line=$total_lines

  sed -n "${start_line},${end_line}p" "$file" | nl -v "$start_line" | while IFS= read -r line; do
    local number
    number=$(echo "$line" | awk '{print $1}')
    local code
    code=$(echo "$line" | cut -d$'\t' -f2-)
    if [ "$number" -eq "$line_num" ]; then
      echo -e "${YELLOW}>>  $number: $code${RESET}"
    else
      echo "    $number: $code"
    fi
  done
}

contains_flag() {
  local flag=$1
  local list=$2
  [[ ",$list," == *",$flag,"* ]]
}

check_dependencies() {
  local binary=${KNIP_CMD%% *}
  if ! command -v "$binary" >/dev/null 2>&1; then
    echo "Required command '$binary' not found. Adjust KNIP_CMD." >&2
    exit 1
  fi

  if ! command -v node >/dev/null 2>&1; then
    echo "Node.js is required to parse Knip output." >&2
    exit 1
  fi

  if ! command -v sed >/dev/null 2>&1 || ! command -v awk >/dev/null 2>&1; then
    echo "Standard POSIX tools (sed, awk) are required." >&2
    exit 1
  fi
}

generate_parser_script() {
  local target=$1
  cat > "$target" <<'NODE'
const fs = require('fs');
const path = require('path');

const [,, reportPath, projectRoot, testPattern, srcDir] = process.argv;
const REPORT = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
const SEP = '\u001f';
const testRegex = testPattern ? new RegExp(testPattern) : null;
const fileCache = new Map();

function gatherFileFlags(relative, raw, hasContent) {
  const flags = [];
  const normalized = relative.replace(/\\/g, '/');
  const ext = path.extname(normalized).replace(/^\./, '');
  if (ext) flags.push(`ext:${ext}`);
  if (testRegex && testRegex.test(normalized)) flags.push('test');
  if (/__tests__|\.spec\.|\.test\./i.test(normalized)) flags.push('test');
  if (/\.stories\.(t|j)sx?$/i.test(normalized) || /\/stories?\//i.test(normalized)) flags.push('story');
  if (/__mocks__|\bmocks?\b/i.test(normalized)) flags.push('mock');
  if (/__fixtures__|\bfixtures?\b/i.test(normalized)) flags.push('fixture');
  if (/\.d\.ts$/i.test(normalized)) flags.push('ambient');
  if (/(^|\/)(config|webpack|rollup|vite)\.[tj]s$/.test(normalized) || /\/config\//i.test(normalized)) flags.push('config');
  if (/(^|\/)(page|layout|error|not-found)\.[tj]sx?$/i.test(normalized) || /\/app\/|\/pages\//i.test(normalized)) flags.push('nextjs');
  if (/\/(api|routes?)\//i.test(normalized) && /\.(ts|js)x?$/i.test(normalized)) flags.push('route');
  if (hasContent) {
    if (/<[A-Z][A-Za-z0-9]*(\s|>)/.test(raw)) flags.push('hasJsx');
    if (/getStaticProps|getServerSideProps|getStaticPaths/.test(raw)) flags.push('nextdata');
  }
  return flags;
}

function getFileData(relative) {
  if (fileCache.has(relative)) {
    return fileCache.get(relative);
  }
  const absolute = path.resolve(projectRoot, relative);
  if (!fs.existsSync(absolute)) {
    const info = { exists: false, absolute, lines: [], trimmed: [], raw: '', flags: gatherFileFlags(relative, '', false) };
    fileCache.set(relative, info);
    return info;
  }
  const raw = fs.readFileSync(absolute, 'utf8');
  const lines = raw.split(/\r?\n/);
  const trimmed = lines.map((line) => line.trim());
  const info = { exists: true, absolute, lines, trimmed, raw, flags: gatherFileFlags(relative, raw, true) };
  fileCache.set(relative, info);
  return info;
}

function escapeRegExp(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function findDefinition(trimmed, symbol) {
  const safe = escapeRegExp(symbol);
  const tests = [
    { regex: new RegExp(`^(?:export\\s+)?(?:async\\s+)?function\\s+${safe}\\b`), type: 'function' },
    { regex: new RegExp(`^(?:export\\s+)?class\\s+${safe}\\b`), type: 'class' },
    { regex: new RegExp(`^(?:export\\s+)?(?:const|let|var)\\s+${safe}\\b`), type: 'variable' },
    { regex: new RegExp(`^(?:export\\s+)?interface\\s+${safe}\\b`), type: 'interface' },
    { regex: new RegExp(`^(?:export\\s+)?type\\s+${safe}\\b`), type: 'type' },
    { regex: new RegExp(`^(?:export\\s+)?enum\\s+${safe}\\b`), type: 'enum' }
  ];
  for (let idx = 0; idx < trimmed.length; idx += 1) {
    const line = trimmed[idx];
    for (const test of tests) {
      if (test.regex.test(line)) {
        return { index: idx, type: test.type, snippet: line };
      }
    }
  }
  return null;
}

function analyzeExport(relative, symbol) {
  const file = getFileData(relative);
  const perSymbolFlags = [];
  if (!file.exists) {
    return { line: '', itemType: 'missing', snippet: '', flags: [...file.flags, ...perSymbolFlags] };
  }

  const { trimmed, raw } = file;
  let index = -1;
  let itemType = 'unknown';
  let snippet = '';
  const safe = escapeRegExp(symbol);

  const assign = (idx, type, overrideSnippet) => {
    if (idx !== -1) {
      index = idx;
      if (type) itemType = type;
      snippet = typeof overrideSnippet === 'string' ? overrideSnippet : trimmed[idx];
      return true;
    }
    return false;
  };

  if (symbol === 'default') {
    for (let i = 0; i < trimmed.length; i += 1) {
      const line = trimmed[i];
      let match;
      if ((match = line.match(/^export\s+default\s+class\s+([A-Za-z0-9_]+)/))) {
        assign(i, 'class');
        if (match[1] && /^[A-Z]/.test(match[1]) && file.flags.includes('hasJsx')) {
          perSymbolFlags.push('reactcomponent');
        }
        break;
      }
      if ((match = line.match(/^export\s+default\s+(?:async\s+)?function\s+([A-Za-z0-9_]+)/))) {
        assign(i, 'function');
        if (match[1] && /^[A-Z]/.test(match[1]) && file.flags.includes('hasJsx')) {
          perSymbolFlags.push('reactcomponent');
        }
        break;
      }
      if ((match = line.match(/^export\s+default\s+(?:const|let|var)\s+([A-Za-z0-9_]+)/))) {
        assign(i, 'variable');
        const definition = findDefinition(trimmed, match[1]);
        if (definition) {
          index = definition.index;
          itemType = definition.type;
          snippet = definition.snippet;
        }
        break;
      }
      if ((match = line.match(/^export\s+default\s+([A-Za-z0-9_]+)\s*;?/))) {
        perSymbolFlags.push('reexport');
        const definition = findDefinition(trimmed, match[1]);
        if (definition) {
          index = definition.index;
          itemType = definition.type;
          snippet = definition.snippet;
        } else {
          assign(i, 'reference');
        }
        break;
      }
      if (/^export\s+default\s*{/.test(line) && line.includes(':')) {
        assign(i, 'object');
        break;
      }
      if (line.startsWith('export default') && /=>|function|\(|class|{/.test(line)) {
        assign(i, 'expression');
        break;
      }
      if (/^export\s*{\s*[A-Za-z0-9_]+\s+as\s+default/.test(line)) {
        perSymbolFlags.push('reexport');
        assign(i, 'reexport');
        break;
      }
    }
  } else {
    const tests = [
      { regex: new RegExp(`^export\\s+(?:async\\s+)?function\\s+${safe}\\b`), type: 'function' },
      { regex: new RegExp(`^export\\s+class\\s+${safe}\\b`), type: 'class' },
      { regex: new RegExp(`^export\\s+(?:const|let|var)\\s+${safe}\\b`), type: 'variable' },
      { regex: new RegExp(`^export\\s+interface\\s+${safe}\\b`), type: 'interface' },
      { regex: new RegExp(`^export\\s+type\\s+${safe}\\b`), type: 'type' },
      { regex: new RegExp(`^export\\s+enum\\s+${safe}\\b`), type: 'enum' }
    ];
    for (const test of tests) {
      for (let i = 0; i < trimmed.length; i += 1) {
        if (test.regex.test(trimmed[i])) {
          assign(i, test.type);
          break;
        }
      }
      if (index !== -1) break;
    }

    if (index === -1) {
      for (let i = 0; i < trimmed.length; i += 1) {
        const line = trimmed[i];
        if (/^export\s*{/.test(line) && line.includes(symbol)) {
          perSymbolFlags.push('reexport');
          assign(i, 'reexport');
          const definition = findDefinition(trimmed, symbol);
          if (definition) {
            index = definition.index;
            itemType = definition.type;
            snippet = definition.snippet;
          }
          break;
        }
      }
    }
  }

  if (index === -1) {
    const fallback = findDefinition(trimmed, symbol);
    if (fallback) {
      index = fallback.index;
      itemType = fallback.type;
      snippet = fallback.snippet;
    }
  }

  if (index !== -1 && itemType === 'unknown') {
    const line = trimmed[index];
    if (/function\b/.test(line)) itemType = 'function';
    else if (/class\b/.test(line)) itemType = 'class';
    else if (/enum\b/.test(line)) itemType = 'enum';
    else if (/\binterface\b/.test(line)) itemType = 'interface';
    else if (/\btype\b/.test(line)) itemType = 'type';
    else if (/\bconst\b|\blet\b|\bvar\b/.test(line)) itemType = 'variable';
  }

  if (symbol === 'default') perSymbolFlags.push('default');
  else perSymbolFlags.push('named');

  if (symbol !== 'default' && /^use[A-Z]/.test(symbol)) perSymbolFlags.push('hook');
  if (itemType === 'function' && symbol !== 'default' && /^[A-Z]/.test(symbol) && file.flags.includes('hasJsx')) {
    perSymbolFlags.push('reactcomponent');
  }
  if (itemType === 'class' && file.flags.includes('hasJsx')) {
    perSymbolFlags.push('reactcomponent');
  }

  if (index > 0) {
    for (let offset = 1; offset <= 3 && index - offset >= 0; offset += 1) {
      const prev = trimmed[index - offset];
      if (prev.startsWith('@')) {
        perSymbolFlags.push('decorated');
        break;
      }
    }
  }

  if (symbol !== 'default' && trimmed[index] && trimmed[index].includes(' as ')) {
    perSymbolFlags.push('alias');
  }

  if (itemType === 'interface' || itemType === 'type') {
    perSymbolFlags.push('typesonly');
  }

  if (raw.includes(`'${symbol}'`) || raw.includes(`"${symbol}"`) || raw.includes('`' + symbol + '`')) {
    perSymbolFlags.push('stringLiteral');
  }
  if (raw.includes(`['${symbol}']`) || raw.includes(`["${symbol}"]`)) {
    perSymbolFlags.push('computed');
  }

  const uniqueFlags = Array.from(new Set([...file.flags, ...perSymbolFlags]));
  const normalizedSnippet = snippet.replace(/\s+/g, ' ').slice(0, 160);
  return { line: index === -1 ? '' : String(index + 1), itemType, snippet: normalizedSnippet, flags: uniqueFlags.join(',') };
}

function analyzeFile(relative) {
  const file = getFileData(relative);
  const flags = file.flags;
  return { flags: Array.from(new Set(flags)).join(','), itemType: 'file' };
}

function emit(columns) {
  process.stdout.write(columns.join(SEP));
  process.stdout.write('\n');
}

const handled = new Set();

const unusedExports = Array.isArray(REPORT.unusedExports) ? REPORT.unusedExports : [];
for (const entry of unusedExports) {
  const file = entry.file || entry.filePath || entry.src;
  if (!file) continue;
  const symbol = entry.export || entry.name || entry.identifier || entry.token || 'default';
  const info = analyzeExport(file, symbol);
  emit(['EXPORT', file, symbol, info.line, info.itemType, info.flags, info.snippet]);
  handled.add(file);
}

const unusedFiles = Array.isArray(REPORT.unusedFiles) ? REPORT.unusedFiles : [];
for (const entry of unusedFiles) {
  const file = typeof entry === 'string' ? entry : entry.file || entry.path;
  if (!file) continue;
  const info = analyzeFile(file);
  emit(['FILE', file, path.basename(file), '', info.itemType, info.flags, '']);
  handled.add(file);
}

const unusedMembers = Array.isArray(REPORT.unusedMembers) ? REPORT.unusedMembers : [];
for (const entry of unusedMembers) {
  const file = entry.file || entry.filePath;
  if (!file) continue;
  const symbol = entry.member || entry.name || entry.identifier || entry.key || 'member';
  const info = analyzeExport(file, symbol);
  emit(['MEMBER', file, symbol, info.line, info.itemType, info.flags, info.snippet]);
  handled.add(file);
}

const unusedTypes = Array.isArray(REPORT.unusedTypes) ? REPORT.unusedTypes : [];
for (const entry of unusedTypes) {
  const file = entry.file || entry.filePath;
  if (!file) continue;
  const symbol = entry.type || entry.name || entry.identifier || 'type';
  const info = analyzeExport(file, symbol);
  emit(['TYPE', file, symbol, info.line, info.itemType, info.flags, info.snippet]);
  handled.add(file);
}
NODE
}

run_knip() {
  local output_json=$1
  local cmd="$KNIP_CMD --reporter json"
  [ -n "$KNIP_CONFIG" ] && cmd+=" --config \"$KNIP_CONFIG\""
  [ -n "$KNIP_ARGS" ] && cmd+=" $KNIP_ARGS"
  run_cmd "$cmd > \"$output_json\""
}

classify_item() {
  local kind=$1
  local file=$2
  local symbol=$3
  local line=$4
  local item_type=$5
  local flags=$6

  local verdict="REMOVE"
  local reason="No indicators that the symbol is consumed indirectly."

  if contains_flag "ambient" "$flags"; then
    verdict="KEEP"
    reason="Ambient declarations are consumed by the TypeScript compiler."
    echo "$verdict|$reason"
    return
  fi

  if contains_flag "nextjs" "$flags" || contains_flag "route" "$flags" || contains_flag "nextdata" "$flags"; then
    verdict="KEEP"
    reason="File-based framework conventions (Next.js / route handlers) rely on these exports."
    echo "$verdict|$reason"
    return
  fi

  if contains_flag "config" "$flags"; then
    verdict="REVIEW"
    reason="Configuration files or exports may be pulled in dynamically."
    echo "$verdict|$reason"
    return
  fi

  if contains_flag "test" "$flags"; then
    verdict="TEST_ONLY"
    reason="Located in a test context; ensure tests truly do not require this."
    echo "$verdict|$reason"
    return
  fi

  if contains_flag "story" "$flags"; then
    verdict="REVIEW"
    reason="Storybook artifacts can be referenced dynamically."
    echo "$verdict|$reason"
    return
  fi

  if contains_flag "mock" "$flags" || contains_flag "fixture" "$flags"; then
    verdict="REVIEW"
    reason="Fixture or mock utilities may be loaded via dynamic resolution."
    echo "$verdict|$reason"
    return
  fi

  if [ "$kind" = "FILE" ]; then
    echo "$verdict|$reason"
    return
  fi

  if contains_flag "decorated" "$flags"; then
    verdict="REVIEW"
    reason="Decorators often register symbols with frameworks at runtime."
  elif contains_flag "reactcomponent" "$flags"; then
    verdict="REVIEW"
    reason="Component-like exports may be referenced from JSX via dynamic composition."
  elif contains_flag "hook" "$flags"; then
    verdict="REVIEW"
    reason="Custom hooks are frequently consumed in test or dynamic contexts."
  elif contains_flag "stringLiteral" "$flags" || contains_flag "computed" "$flags"; then
    verdict="REVIEW"
    reason="Detected string/computed property access suggesting dynamic usage."
  elif contains_flag "reexport" "$flags" || contains_flag "alias" "$flags"; then
    verdict="REVIEW"
    reason="Re-export or alias patterns may hide actual consumers."
  elif contains_flag "typesonly" "$flags"; then
    verdict="REVIEW"
    reason="Type-only artifacts can appear unused but affect public interfaces."
  fi

  echo "$verdict|$reason"
}

summarize_results() {
  local analysis_file=$1
  local total=$2

  print_header "SUMMARY"
  echo ""
  echo "Total candidates analyzed: $total"
  local categories=("REMOVE" "REVIEW" "KEEP" "TEST_ONLY")
  for category in "${categories[@]}"; do
    local count
    count=$(grep -c "|$category|" "$analysis_file" 2>/dev/null || echo 0)
    local color=""
    case "$category" in
      REMOVE) color=$GREEN ;;
      REVIEW) color=$YELLOW ;;
      KEEP) color=$RED ;;
      TEST_ONLY) color=$YELLOW ;;
    esac
    echo -e "  ${color}${category}${RESET}: $count"
  done

  if [ -s "$analysis_file" ]; then
    echo ""
    echo "Actionable Items:"

    if grep -q "|REMOVE|" "$analysis_file"; then
      echo ""
      echo -e "${GREEN}[SAFE TO REMOVE]${RESET}"
      grep "|REMOVE|" "$analysis_file" | while IFS='|' read -r sym verdict file line type; do
        echo "  - $sym ($type) in $file${line:+:$line}"
      done
    fi

    if grep -q "|REVIEW|" "$analysis_file"; then
      echo ""
      echo -e "${YELLOW}[NEEDS REVIEW]${RESET}"
      grep "|REVIEW|" "$analysis_file" | while IFS='|' read -r sym verdict file line type; do
        echo "  - $sym ($type) in $file${line:+:$line}"
      done
    fi

    if grep -q "|KEEP|" "$analysis_file"; then
      echo ""
      echo -e "${RED}[DO NOT REMOVE]${RESET}"
      grep "|KEEP|" "$analysis_file" | while IFS='|' read -r sym verdict file line type; do
        echo "  - $sym ($type) in $file${line:+:$line}"
      done
    fi

    if grep -q "|TEST_ONLY|" "$analysis_file"; then
      echo ""
      echo -e "${YELLOW}[TEST-ONLY CANDIDATES]${RESET}"
      grep "|TEST_ONLY|" "$analysis_file" | while IFS='|' read -r sym verdict file line type; do
        echo "  - $sym ($type) in $file${line:+:$line}"
      done
    fi
  fi
}

main() {
  print_header "KNIP DEAD CODE ANALYSIS"
  echo "Source directory: $SRC_DIR"
  [ -n "$KNIP_CONFIG" ] && echo "Knip config: $KNIP_CONFIG"
  [ -n "$KNIP_ARGS" ] && echo "Extra Knip args: $KNIP_ARGS"
  echo ""
  check_dependencies

  print_subheader "Analyzing project with Knip"

  local tmpdir
  tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t knip-analysis)
  trap 'rm -rf "$tmpdir"' EXIT

  local report_json="$tmpdir/knip-report.json"
  run_knip "$report_json"

  if [ ! -s "$report_json" ]; then
    echo "Knip did not produce output." >&2
    exit 1
  fi

  local parser="$tmpdir/parse_knip.js"
  generate_parser_script "$parser"

  local items_file="$tmpdir/candidates.txt"
  node "$parser" "$report_json" "$PWD" "$TEST_PATTERNS" "$SRC_DIR" > "$items_file"

  if [ ! -s "$items_file" ]; then
    echo ""
    echo "No unused exports, members, types, or files were reported by Knip."
    exit 0
  fi

  local analysis_file="$tmpdir/analysis_results.txt"
  : > "$analysis_file"

  local total=0
  while IFS="$FIELD_SEP" read -r kind file symbol line item_type flags snippet; do
    [ -z "$kind" ] && continue
    total=$((total + 1))
    local location="$file"
    [ -n "$line" ] && location="$file:$line"

    local header="$symbol"
    if [ "$kind" = "FILE" ]; then
      header="$file"
    fi

    print_subheader "$header"
    echo "Kind: $kind"
    echo "Location: $location"
    [ -n "$item_type" ] && echo "Item type: $item_type"
    if [ -n "$flags" ] && [ "$VERBOSE" -ge 1 ]; then
      echo "Flags: $flags"
    fi
    if [ -n "$snippet" ] && [ "$VERBOSE" -ge 1 ]; then
      echo "Snippet: $snippet"
    fi

    show_code_context "$file" "$line"

    local verdict_info
    verdict_info=$(classify_item "$kind" "$file" "$symbol" "$line" "$item_type" "$flags")
    local verdict=${verdict_info%%|*}
    local reason=${verdict_info#*|}

    case "$verdict" in
      REMOVE)
        echo -e "${GREEN}REMOVE${RESET} - $reason"
        ;;
      REVIEW)
        echo -e "${YELLOW}REVIEW${RESET} - $reason"
        ;;
      KEEP)
        echo -e "${RED}KEEP${RESET} - $reason"
        ;;
      TEST_ONLY)
        echo -e "${YELLOW}TEST ONLY${RESET} - $reason"
        ;;
      *)
        verdict="REVIEW"
        echo -e "${YELLOW}REVIEW${RESET} - $reason"
        ;;
    esac

    echo "$symbol|$verdict|$file|$line|$item_type" >> "$analysis_file"
  done < "$items_file"

  summarize_results "$analysis_file" "$total"
}

main "$@"
