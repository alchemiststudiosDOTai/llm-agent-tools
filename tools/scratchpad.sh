#!/usr/bin/env bash
set -euo pipefail

# scratchpad - External memory for LLM agent reasoning
# Records intermediate states between reasoning steps
# Implements "Program of Thoughts" / "Chain of Code" state tracking

readonly VERSION="2.0.0"
readonly DEFAULT_FILE="/tmp/scratchpad.json"

# Defaults
scratchpad="$DEFAULT_FILE"
output_format="json" # Default for this tool is JSON as it's state-heavy
verbose=false

usage() {
    cat >&2 <<EOF
scratchpad v${VERSION} - External memory for reasoning

USAGE:
    scratchpad [OPTIONS] <COMMAND> [ARGS]

OPTIONS:
    -f, --file <PATH>     Scratchpad file (default: $DEFAULT_FILE)
    -o, --output <FMT>    Output format: json, markdown (default: json)
    -v, --verbose         Enable verbose output
    -h, --help            Show this help

COMMANDS:
    get [KEY]             Get current state (or specific key)
    set <JSON>            Set entire state
    update <KEY> <VAL>    Update a specific key
    push <KEY> <VAL>      Push value to array at key
    pop <KEY>             Pop value from array at key
    log <MSG>             Append to reasoning log
    history               Show state change history
    clear                 Clear scratchpad

EXAMPLES:
    scratchpad set '{"peg_A": [3,2,1], "peg_B": [], "peg_C": []}'
    scratchpad push peg_C 1
    scratchpad -o markdown get
    scratchpad log "Moving disk 1 to C"
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

# --- Helpers ---

init_scratchpad() {
    if [[ ! -f "$scratchpad" ]]; then
        log "Initializing scratchpad at $scratchpad"
        echo '{"state": {}, "log": [], "history": []}' > "$scratchpad"
    fi
}

format_output() {
    local json="$1"
    
    if [[ "$output_format" == "json" ]]; then
        echo "$json" | jq .
    else
        # Markdown Output
        # Simple recursion for pretty printing
        echo "$json" | jq -r '
            def to_md:
                if type == "object" then
                    to_entries | map("- **\(.key)**: \(.value | tojson)") | .[]
                elif type == "array" then
                    map("- \(.tojson)") | .[]
                else
                    .
                end;
            to_md
        '
    fi
}

write_response() {
    local msg="$1"
    local data="${2:-null}"
    
    if [[ "$output_format" == "json" ]]; then
        # data is expected to be a valid JSON string or "null"
        echo "{ \"status\": \"success\", \"message\": \"$msg\", \"data\": $data }" | jq .
    else
        echo "$msg"
    fi
}

# --- Commands ---

cmd_get() {
    init_scratchpad
    local key="${1:-}"
    local data
    
    if [[ -z "$key" ]]; then
        data=$(cat "$scratchpad" | jq '.state')
    else
        data=$(cat "$scratchpad" | jq --arg k "$key" '.state[$k]')
        if [[ "$data" == "null" ]]; then
            die "key '$key' not found"
        fi
    fi
    
    format_output "$data"
}

cmd_set() {
    local new_state="$1"
    init_scratchpad

    echo "$new_state" | jq . >/dev/null 2>&1 || die "invalid JSON"

    local timestamp=$(date -Iseconds)
    
    # Atomic update with temp file
    cat "$scratchpad" | jq --argjson new "$new_state" --arg ts "$timestamp" '
        .history += [{"timestamp": $ts, "action": "set", "state": $new}] |
        .state = $new
    ' > "${scratchpad}.tmp" && mv "${scratchpad}.tmp" "$scratchpad"

    write_response "State set" "$new_state"
}

cmd_update() {
    local key="$1"
    local value="$2"
    init_scratchpad

    local timestamp=$(date -Iseconds)
    local json_val="$value"

    # Try to parse as JSON, else treat as string
    if ! echo "$value" | jq . >/dev/null 2>&1; then
        json_val=$(jq -n --arg v "$value" '$v')
    fi

    cat "$scratchpad" | jq --arg k "$key" --argjson v "$json_val" --arg ts "$timestamp" '
        .history += [{"timestamp": $ts, "action": "update", "key": $k, "value": $v}] |
        .state[$k] = $v
    ' > "${scratchpad}.tmp" && mv "${scratchpad}.tmp" "$scratchpad"

    write_response "Updated $key" "$json_val"
}

cmd_push() {
    local key="$1"
    local value="$2"
    init_scratchpad

    local timestamp=$(date -Iseconds)
    local json_val="$value"

    if ! echo "$value" | jq . >/dev/null 2>&1; then
        json_val=$(jq -n --arg v "$value" '$v')
    fi

    # Ensure key is an array or null before pushing
    local current_type=$(cat "$scratchpad" | jq -r --arg k "$key" '.state[$k] | type')
    if [[ "$current_type" != "null" && "$current_type" != "array" ]]; then
        die "Cannot push to '$key': current value is not an array (is $current_type)"
    fi

    cat "$scratchpad" | jq --arg k "$key" --argjson v "$json_val" --arg ts "$timestamp" '
        if .state[$k] == null then .state[$k] = [] else . end |
        .history += [{"timestamp": $ts, "action": "push", "key": $k, "value": $v}] |
        .state[$k] += [$v]
    ' > "${scratchpad}.tmp" && mv "${scratchpad}.tmp" "$scratchpad"

    write_response "Pushed to $key" "$json_val"
}

cmd_pop() {
    local key="$1"
    init_scratchpad

    local timestamp=$(date -Iseconds)
    
    local popped
    popped=$(cat "$scratchpad" | jq --arg k "$key" '.state[$k][-1]')
    
    if [[ "$popped" == "null" ]]; then
        die "Cannot pop from '$key': empty or null"
    fi

    cat "$scratchpad" | jq --arg k "$key" --arg ts "$timestamp" ' 
        .history += [{"timestamp": $ts, "action": "pop", "key": $k, "value": .state[$k][-1]}] |
        .state[$k] = .state[$k][:-1]
    ' > "${scratchpad}.tmp" && mv "${scratchpad}.tmp" "$scratchpad"

    if [[ "$output_format" == "json" ]]; then
        write_response "Popped from $key" "$popped"
    else
        echo "$popped" | jq -r . # unquote if string
    fi
}

cmd_log() {
    local message="$1"
    init_scratchpad

    local timestamp=$(date -Iseconds)

    cat "$scratchpad" | jq --arg msg "$message" --arg ts "$timestamp" '
        .log += [{"timestamp": $ts, "message": $msg}]
    ' > "${scratchpad}.tmp" && mv "${scratchpad}.tmp" "$scratchpad"

    write_response "Logged message"
}

cmd_history() {
    init_scratchpad
    local data=$(cat "$scratchpad" | jq '.history')
    format_output "$data"
}

cmd_clear() {
    echo '{"state": {}, "log": [], "history": []}' > "$scratchpad"
    write_response "Scratchpad cleared"
}

# --- Main ---

# 1. Parse Global Options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file) 
            scratchpad="$2"
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
            break
            ;; 
        *)
            break
            ;; 
    esac
done

[[ $# -eq 0 ]] && usage

command="$1"
shift

case "$command" in
    get)
        cmd_get "$@"
        ;; 
    set)
        [[ $# -lt 1 ]] && die "set requires JSON argument"
        cmd_set "$1"
        ;; 
    update)
        [[ $# -lt 2 ]] && die "update requires key and value"
        cmd_update "$1" "$2"
        ;; 
    push)
        [[ $# -lt 2 ]] && die "push requires key and value"
        cmd_push "$1" "$2"
        ;; 
    pop)
        [[ $# -lt 1 ]] && die "pop requires key"
        cmd_pop "$1"
        ;; 
    log)
        [[ $# -lt 1 ]] && die "log requires message"
        cmd_log "$*"
        ;; 
    history)
        cmd_history
        ;; 
    clear)
        cmd_clear
        ;; 
    *)
        die "unknown command: $command"
        ;; 
esac