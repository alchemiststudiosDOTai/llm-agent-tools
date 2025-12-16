#!/usr/bin/env bash
set -euo pipefail

# scratchpad - External memory for LLM agent reasoning
# Records intermediate states between reasoning steps

readonly VERSION="1.0.0"
readonly DEFAULT_FILE="/tmp/scratchpad.json"

usage() {
    cat >&2 <<EOF
scratchpad v${VERSION} - External memory for reasoning

USAGE:
    scratchpad <command> [args]

COMMANDS:
    get [key]           Get current state (or specific key)
    set <json>          Set entire state
    update <key> <val>  Update a specific key
    push <key> <val>    Push value to array at key
    pop <key>           Pop value from array at key
    log <message>       Append to reasoning log
    history             Show state change history
    clear               Clear scratchpad

OPTIONS:
    -f, --file <PATH>   Scratchpad file (default: $DEFAULT_FILE)
    -h, --help          Show this help

EXAMPLES:
    # Initialize state for Tower of Hanoi
    scratchpad set '{"peg_A": [3,2,1], "peg_B": [], "peg_C": [], "moves": 0}'

    # Move disk: pop from A, push to C
    scratchpad pop peg_A
    scratchpad push peg_C 1
    scratchpad update moves 1

    # Check current state
    scratchpad get

    # Log reasoning
    scratchpad log "Moving smallest disk to peg C"

    # View history
    scratchpad history
EOF
    exit 1
}

die() {
    echo "error: $*" >&2
    exit 1
}

# Initialize scratchpad file if needed
init_scratchpad() {
    if [[ ! -f "$scratchpad" ]]; then
        echo '{"state": {}, "log": [], "history": []}' > "$scratchpad"
    fi
}

# Get current state
cmd_get() {
    init_scratchpad
    local key="${1:-}"
    if [[ -z "$key" ]]; then
        cat "$scratchpad" | jq '.state'
    else
        cat "$scratchpad" | jq -r --arg k "$key" '.state[$k]'
    fi
}

# Set entire state
cmd_set() {
    local new_state="$1"
    init_scratchpad

    # Validate JSON
    echo "$new_state" | jq . >/dev/null 2>&1 || die "invalid JSON"

    # Record in history
    local timestamp
    timestamp=$(date -Iseconds)

    cat "$scratchpad" | jq --argjson new "$new_state" --arg ts "$timestamp" '
        .history += [{"timestamp": $ts, "action": "set", "state": $new}] |
        .state = $new
    ' > "${scratchpad}.tmp" && mv "${scratchpad}.tmp" "$scratchpad"

    echo "state set"
}

# Update specific key
cmd_update() {
    local key="$1"
    local value="$2"
    init_scratchpad

    local timestamp
    timestamp=$(date -Iseconds)

    # Try to parse as JSON, fall back to string
    if echo "$value" | jq . >/dev/null 2>&1; then
        cat "$scratchpad" | jq --arg k "$key" --argjson v "$value" --arg ts "$timestamp" '
            .history += [{"timestamp": $ts, "action": "update", "key": $k, "value": $v}] |
            .state[$k] = $v
        ' > "${scratchpad}.tmp" && mv "${scratchpad}.tmp" "$scratchpad"
    else
        cat "$scratchpad" | jq --arg k "$key" --arg v "$value" --arg ts "$timestamp" '
            .history += [{"timestamp": $ts, "action": "update", "key": $k, "value": $v}] |
            .state[$k] = $v
        ' > "${scratchpad}.tmp" && mv "${scratchpad}.tmp" "$scratchpad"
    fi

    echo "updated $key"
}

# Push to array
cmd_push() {
    local key="$1"
    local value="$2"
    init_scratchpad

    local timestamp
    timestamp=$(date -Iseconds)

    # Try to parse as JSON number/value
    if echo "$value" | jq . >/dev/null 2>&1; then
        cat "$scratchpad" | jq --arg k "$key" --argjson v "$value" --arg ts "$timestamp" '
            .history += [{"timestamp": $ts, "action": "push", "key": $k, "value": $v}] |
            .state[$k] += [$v]
        ' > "${scratchpad}.tmp" && mv "${scratchpad}.tmp" "$scratchpad"
    else
        cat "$scratchpad" | jq --arg k "$key" --arg v "$value" --arg ts "$timestamp" '
            .history += [{"timestamp": $ts, "action": "push", "key": $k, "value": $v}] |
            .state[$k] += [$v]
        ' > "${scratchpad}.tmp" && mv "${scratchpad}.tmp" "$scratchpad"
    fi

    echo "pushed to $key"
}

# Pop from array
cmd_pop() {
    local key="$1"
    init_scratchpad

    local timestamp
    timestamp=$(date -Iseconds)

    # Get and display the popped value
    local popped
    popped=$(cat "$scratchpad" | jq -r --arg k "$key" '.state[$k][-1]')

    cat "$scratchpad" | jq --arg k "$key" --arg ts "$timestamp" --arg popped "$popped" '
        .history += [{"timestamp": $ts, "action": "pop", "key": $k, "value": $popped}] |
        .state[$k] = .state[$k][:-1]
    ' > "${scratchpad}.tmp" && mv "${scratchpad}.tmp" "$scratchpad"

    echo "$popped"
}

# Log reasoning
cmd_log() {
    local message="$1"
    init_scratchpad

    local timestamp
    timestamp=$(date -Iseconds)

    cat "$scratchpad" | jq --arg msg "$message" --arg ts "$timestamp" '
        .log += [{"timestamp": $ts, "message": $msg}]
    ' > "${scratchpad}.tmp" && mv "${scratchpad}.tmp" "$scratchpad"

    echo "logged"
}

# Show history
cmd_history() {
    init_scratchpad
    cat "$scratchpad" | jq '.history'
}

# Show log
cmd_showlog() {
    init_scratchpad
    cat "$scratchpad" | jq -r '.log[] | "[\(.timestamp)] \(.message)"'
}

# Clear scratchpad
cmd_clear() {
    echo '{"state": {}, "log": [], "history": []}' > "$scratchpad"
    echo "cleared"
}

# Main
scratchpad="$DEFAULT_FILE"

# Parse global options first
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file)
            scratchpad="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            die "unknown option: $1"
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
        cmd_get "${1:-}"
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
    showlog)
        cmd_showlog
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
