#!/usr/bin/env bash
set -euo pipefail

# list-tools - Discover available LLM agent tools
# Lists all tools in this project with their descriptions

readonly VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
output_format="markdown"
verbose=false

usage() {
    cat >&2 <<EOF
list-tools v${VERSION} - Discover available LLM agent tools

USAGE:
    list-tools [OPTIONS]

OPTIONS:
    -o, --output <FMT>    Output format: markdown, json (default: markdown)
    -v, --verbose         Show full tool descriptions
    -h, --help            Show this help

EXAMPLES:
    list-tools                    # List tools as markdown table
    list-tools -o json            # List tools as JSON
    list-tools -v                 # Include full descriptions
EOF
    exit 1
}

die() {
    echo "error: $*" >&2
    exit 1
}

log() {
    [[ "$verbose" == true ]] && echo "debug: $*" >&2 || true
}

# --- Helpers ---

get_tool_description() {
    local script="$1"
    local name
    name=$(basename "$script" .sh)

    # Look for pattern: # tool-name - Description (in first 10 lines)
    head -10 "$script" | grep -E "^# ${name} - " | sed "s/^# ${name} - //" | head -1
}

get_tool_version() {
    local script="$1"
    grep -E "^readonly VERSION=" "$script" 2>/dev/null | head -1 | sed 's/.*VERSION=["'\'']\([^"'\'']*\)['\''"].*/\1/' || echo ""
}

get_full_description() {
    local script="$1"
    # Get all comment lines after the shebang and set commands, up to first blank line
    awk '
        NR == 1 { next }                    # Skip shebang
        /^set -/ { next }                   # Skip set commands
        /^$/ { exit }                       # Stop at first blank line
        /^# / { sub(/^# /, ""); print }     # Print comment content
    ' "$script" | paste -sd ' ' -
}

# --- Output Formatters ---

format_json() {
    local tools_json="["
    local first=true

    for script in "$SCRIPT_DIR"/*.sh; do
        [[ ! -x "$script" ]] && continue

        local name
        name=$(basename "$script")

        # Skip meta-tools
        [[ "$name" == "list-tools.sh" ]] && continue
        [[ "$name" == "verify-tools.sh" ]] && continue

        local desc version full_desc
        desc=$(get_tool_description "$script")
        version=$(get_tool_version "$script")

        [[ -z "$desc" ]] && desc="No description"
        [[ -z "$version" ]] && version="unknown"

        if [[ "$first" == true ]]; then
            first=false
        else
            tools_json+=","
        fi

        if [[ "$verbose" == true ]]; then
            full_desc=$(get_full_description "$script")
            tools_json+=$(jq -n \
                --arg name "$name" \
                --arg path "./tools/$name" \
                --arg version "$version" \
                --arg desc "$desc" \
                --arg full "$full_desc" \
                '{name: $name, path: $path, version: $version, description: $desc, details: $full}')
        else
            tools_json+=$(jq -n \
                --arg name "$name" \
                --arg path "./tools/$name" \
                --arg version "$version" \
                --arg desc "$desc" \
                '{name: $name, path: $path, version: $version, description: $desc}')
        fi
    done

    tools_json+="]"

    local count
    count=$(echo "$tools_json" | jq 'length')

    jq -n --argjson tools "$tools_json" --argjson count "$count" \
        '{tools: $tools, count: $count}'
}

format_markdown() {
    echo "# Available Tools"
    echo ""
    echo "| Tool | Version | Description |"
    echo "|------|---------|-------------|"

    for script in "$SCRIPT_DIR"/*.sh; do
        [[ ! -x "$script" ]] && continue

        local name
        name=$(basename "$script")

        # Skip meta-tools
        [[ "$name" == "list-tools.sh" ]] && continue
        [[ "$name" == "verify-tools.sh" ]] && continue

        local desc version
        desc=$(get_tool_description "$script")
        version=$(get_tool_version "$script")

        [[ -z "$desc" ]] && desc="No description"
        [[ -z "$version" ]] && version="-"

        echo "| \`$name\` | $version | $desc |"
    done

    echo ""
    echo "Run \`./tools/<tool> -h\` for detailed usage."

    if [[ "$verbose" == true ]]; then
        echo ""
        echo "## Details"
        echo ""

        for script in "$SCRIPT_DIR"/*.sh; do
            [[ ! -x "$script" ]] && continue

            local name
            name=$(basename "$script")

            [[ "$name" == "list-tools.sh" ]] && continue
            [[ "$name" == "verify-tools.sh" ]] && continue

            local full_desc
            full_desc=$(get_full_description "$script")

            if [[ -n "$full_desc" ]]; then
                echo "### $name"
                echo ""
                echo "$full_desc"
                echo ""
            fi
        done
    fi
}

# --- Main ---

while [[ $# -gt 0 ]]; do
    case "$1" in
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
            die "unknown option: $1"
            ;;
        *)
            die "unexpected argument: $1"
            ;;
    esac
done

log "Listing tools from $SCRIPT_DIR"

case "$output_format" in
    json)
        format_json
        ;;
    markdown|*)
        format_markdown
        ;;
esac
