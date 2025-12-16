#!/usr/bin/env bash
set -euo pipefail

# memory-journal - Project context and decision logging
# Captures reasoning and context in a simple markdown file
# https://github.com/neverinfamous/memory-journal-mcp (Concept source)

readonly VERSION="2.0.0"

# Defaults
JOURNAL_FILE="journal.md"
output_format="markdown"
verbose=false

usage() {
    cat >&2 <<EOF
memory-journal v${VERSION} - Project context and decision log

USAGE:
    memory-journal [OPTIONS] <COMMAND> [ARGS]

OPTIONS:
    -f, --file <PATH>     Journal file path (default: journal.md)
    -o, --output <FMT>    Output format: markdown, json (default: markdown)
    -v, --verbose         Enable verbose output
    -h, --help            Show this help

COMMANDS:
    add [OPTIONS] <MSG>   Add a new journal entry
    list [OPTIONS]        List recent entries
    search <QUERY>        Search entries by content

EXAMPLES:
    memory-journal add "Refactored auth logic" -t "refactor,auth"
    memory-journal -o json list -n 5
    memory-journal search "database"
EOF
    exit 1
}

die() {
    echo "error: $*" >&2
    exit 1
}

log() {
    [[ "$verbose" == true ]] && echo "debug: $*" >&2
}

# --- Parsing Helpers ---

parse_markdown_to_json() {
    local file="$1"
    local limit="${2:-0}"
    
    if [[ ! -f "$file" ]]; then
        echo "[]"
        return
    fi

    # AWK script to parse custom markdown format into JSON objects
    # Format:
    # ## 2024-01-01... (`tags`)
    # > Git: ...
    #
    # Content...
    # ---
    
    awk \
    'BEGIN {
        # Helper to print valid JSON line
    }
    /^## / {
        if (ts != "") {
            print_json(ts, tags, git, content)
        }
        
        # Reset state
        ts = ""; tags = ""; git = ""; content = ""
        
        # Parse Header
        line = $0
        sub(/^## /, "", line)
        
        # Extract tags: (`tag1,tag2`)
        if (match(line, /\(`[^`]+`\)/)) {
            t = substr(line, RSTART, RLENGTH)
            gsub(/[()`]/, "", t)
            tags = t
            sub(/ \(`[^`]+`\)/, "", line)
        }
        # Trim timestamp
        gsub(/^[ \t]+|[ \t]+$/, "", line)
        ts = line
        next
    }
    /^> Git: / {
        git = substr($0, 8)
        next
    }
    /^---$/ {
        next
    }
    {
        if (ts != "") {
             # Escape for JSON string: backslash then quote
             gsub(/\\/, "\\\\")
             gsub(/"/, "\\\"")
             
             if (content != "") content = content "\n"
             content = content $0
        }
    }
    END {
        if (ts != "") {
            print_json(ts, tags, git, content)
        }
    }
    
    function print_json(t, tag, g, c) {
        # Trim leading/trailing newlines from content
        gsub(/^\\n+|\\n+$/, "", c)
        printf "{\"timestamp\": \"%s\", \"tags\": \"%s\", \"git\": \"%s\", \"content\": \"%s\"}\n", t, tag, g, c
    }
    ' "$file" | jq -s "sort_by(.timestamp) | reverse | .[0:$limit]"
}

# --- Command Implementations ---

cmd_add() {
    local tags=""
    local msg=""
    
    # Parse Command Args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--tags) 
                tags="$2"
                shift 2
                ;; 
            -*) 
                die "unknown option for 'add': $1"
                ;; 
            *) 
                msg="$1"
                shift
                ;; 
        esac
    done

    [[ -z "$msg" ]] && die "message required for 'add'"

    # 1. Initialize
    if [[ ! -f "$JOURNAL_FILE" ]]; then
        log "Initializing journal at $JOURNAL_FILE"
        echo "# Project Memory Journal" > "$JOURNAL_FILE"
        echo "" >> "$JOURNAL_FILE"
    fi
    
    # 2. Prepare Data
    local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    local git_context=""
    
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local branch=$(git branch --show-current)
        local hash=$(git rev-parse --short HEAD)
        git_context="> Git: $branch @ $hash"
    fi
    
    # 3. Write
    # Format:
    # ## TIMESTAMP (`TAGS`)
    # > Git: ...
    #
    # MSG
    #
    # ---
    
    local header="## $timestamp"
    if [[ -n "$tags" ]]; then
        header="$header (\"
$tags\")"
    fi

    {
        echo "$header"
        [[ -n "$git_context" ]] && echo "$git_context"
        echo ""
        echo "$msg"
        echo ""
        echo "---"
        echo ""
    } >> "$JOURNAL_FILE"

    # 4. Output
    if [[ "$output_format" == "json" ]]; then
        jq -n \
            --arg ts "$timestamp" \
            --arg tags "$tags" \
            --arg git "${git_context//> Git: /}" \
            --arg msg "$msg" \
            '{status: "success", entry: {timestamp: $ts, tags: $tags, git: $git, content: $msg}}'
    else
        echo "Entry added to $JOURNAL_FILE"
    fi
}

cmd_list() {
    local num=10
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--num) 
                num="$2"
                shift 2
                ;; 
            -*) 
                die "unknown option for 'list': $1"
                ;; 
            *) 
                die "list accepts no arguments, only options"
                ;; 
        esac
    done

    if [[ ! -f "$JOURNAL_FILE" ]]; then
        if [[ "$output_format" == "json" ]]; then
            echo "[]"
        else
            echo "No journal found at $JOURNAL_FILE"
        fi
        return
    fi

    if [[ "$output_format" == "json" ]]; then
        parse_markdown_to_json "$JOURNAL_FILE" "$num"
    else
        # Markdown Output
        # Find start line for last N entries
        # Count "## " occurrences
        local total_entries=$(grep -c "^## " "$JOURNAL_FILE" || echo 0)
        
        echo "# Journal Entries ($total_entries total, showing last $num)"
        echo ""
        
        if [[ "$total_entries" -eq 0 ]]; then
            echo "No entries."
            return
        fi
        
        # Logic: find the line number of the Nth-to-last "## "
        # 1. Get all line numbers of headers: `grep -n "^## "`
        # 2. Tail N
        # 3. Take head 1
        local start_line=$(grep -n "^## " "$JOURNAL_FILE" | cut -d: -f1 | tail -n "$num" | head -n 1)
        
        if [[ -z "$start_line" ]]; then
            # Should not happen if count > 0, but fallback
            cat "$JOURNAL_FILE"
        else
            tail -n +"$start_line" "$JOURNAL_FILE"
        fi
    fi
}

cmd_search() {
    local query=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -*) 
                die "unknown option for 'search': $1"
                ;; 
            *) 
                query="$1"
                shift
                ;; 
        esac
    done

    [[ -z "$query" ]] && die "search query required"
    if [[ ! -f "$JOURNAL_FILE" ]]; then
        if [[ "$output_format" == "json" ]]; then echo "[]"; else echo "No journal found."; fi
        return
    fi

    if [[ "$output_format" == "json" ]]; then
        # Parse ALL to JSON, then grep via jq?
        # Or Just grep file then try to reconstruct?
        # Safest: Parse all to JSON, filter in jq.
        parse_markdown_to_json "$JOURNAL_FILE" 1000 | jq --arg q "$query" 'map(select(.content | contains($q)) or select(.tags | contains($q)))'
    else
        grep -i -C 2 "$query" "$JOURNAL_FILE" || echo "No matches found."
    fi
}

# --- Main Argument Parsing ---

# 1. Parse Global Options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file) 
            JOURNAL_FILE="$2"
            shift 2
            ;; 
        -o|--output) 
            output_format="$2"
            shift 2
            ;; 
        -v|--verbose) 
            verbose=true
            shift
            ;; 
        -h|--help) 
            usage
            ;; 
        -*) 
            # Break on unknown flag (might be command)
            break
            ;; 
        *) 
            # Command found
            break
            ;; 
    esac
done

[[ $# -eq 0 ]] && usage

command="$1"
shift

case "$command" in
    add) 
        cmd_add "$@"
        ;; 
    list) 
        cmd_list "$@"
        ;; 
    search) 
        cmd_search "$@"
        ;; 
    *) 
        die "unknown command: $command"
        ;; 
esac
