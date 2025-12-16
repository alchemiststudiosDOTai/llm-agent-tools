#!/usr/bin/env bash
set -euo pipefail

# memory-journal.sh - Project context and decision logging
# Pure Markdown version - no JSON, no SQL

readonly VERSION="1.2.0"

# Defaults
JOURNAL_FILE="journal.md"
limit=10
verbose=false

usage() {
    cat >&2 <<EOF
memory-journal v${VERSION} - Project context and decision log

USAGE:
    memory-journal.sh [COMMAND] [OPTIONS]

COMMANDS:
    add <message>       Add a new journal entry
    list                List recent entries
    search <query>      Search entries by content

OPTIONS:
    -n, --num <N>       Number of entries to show (default: ${limit})
    -t, --tags <TAGS>   Comma-separated tags (for add)
    -f, --file <PATH>   Journal file path (default: ${JOURNAL_FILE})
    -v, --verbose       Enable verbose output
    -h, --help          Show this help

EXAMPLES:
    memory-journal.sh add "Refactored auth logic" -t "refactor,auth"
    memory-journal.sh list -n 5
    memory-journal.sh search "database"
EOF
    exit 1
}

die() {
    echo "error: $*" >&2
    exit 1
}

# --- Helpers ---

ensure_init() {
    local file="${1}"
    if [[ ! -f "$file" ]]; then
        [[ "$verbose" == true ]] && echo "Initializing journal at $file" >&2
        echo "# Project Memory Journal" > "$file"
        echo "" >> "$file"
    fi
}

get_git_context() {
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local branch=$(git branch --show-current)
        local hash=$(git rev-parse --short HEAD)
        echo "> Git: $branch @ $hash"
    fi
}

# --- Commands ---

cmd_add() {
    local msg="$1"
    local tags="${2:-}"
    local file="$3"
    
    [[ -z "$msg" ]] && die "message required for 'add'"

    ensure_init "$file"
    
    local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    local bt='`'
    
    # Format Header
    local header="## $timestamp"
    if [[ -n "$tags" ]]; then
        header="$header ($bt$tags$bt)"
    fi

    {
        echo "$header"
        get_git_context
        echo ""
        echo "$msg"
        echo ""
        echo "---"
        echo ""
    } >> "$file"
    
    echo "Entry added to $file"
}

cmd_list() {
    local file="$1"
    local num="$2"

    if [[ ! -f "$file" ]]; then
        die "No journal found at $file"
    fi

    # Find the line number of the Nth-to-last "## " header
    local start_line=$(grep -n "^## " "$file" | tail -n "$num" | head -n 1 | cut -d: -f1)

    if [[ -z "$start_line" ]]; then
        cat "$file"
    else
        tail -n "+$start_line" "$file"
    fi
}

cmd_search() {
    local query="$1"
    local file="$2"

    [[ -z "$query" ]] && die "search query required"
    
    if [[ ! -f "$file" ]]; then
        die "No journal found at $file"
    fi

    # Simple grep with context
    grep -i -C 2 "$query" "$file" || echo "No matches found."
}

# --- Main ---

command=""
args=()
tags=""

# Parse Args
while [[ $# -gt 0 ]]; do
    case "$1" in
        add|list|search)
            command="$1"
            shift
            ;;
        -n|--num)
            limit="$2"
            shift 2
            ;;
        -t|--tags)
            tags="$2"
            shift 2
            ;;
        -f|--file)
            JOURNAL_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            verbose=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            args+=("$1")
            shift
            ;;
    esac
done

[[ -z "$command" ]] && usage

case "$command" in
    add)
        cmd_add "${args[*]}" "$tags" "$JOURNAL_FILE"
        ;;
    list)
        cmd_list "$JOURNAL_FILE" "$limit"
        ;;
    search)
        cmd_search "${args[*]}" "$JOURNAL_FILE"
        ;;
esac