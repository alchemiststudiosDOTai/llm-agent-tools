#!/usr/bin/env bash
set -euo pipefail

# verify-tools - Validate tool compliance with project standards
# Tests help output, JSON validity, and shellcheck analysis

readonly VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
output_format="markdown"
verbose=false
skip_shellcheck=false

# Test counters
declare -i total_tests=0
declare -i passed_tests=0
declare -i failed_tests=0
declare -i skipped_tests=0

# Results storage
declare -a results=()
declare -a issues=()

usage() {
    cat >&2 <<EOF
verify-tools v${VERSION} - Validate tool compliance

USAGE:
    verify-tools [OPTIONS] [TOOL...]

OPTIONS:
    -o, --output <FMT>    Output format: markdown, json (default: markdown)
    -v, --verbose         Show detailed test output
    --skip-shellcheck     Skip shellcheck analysis
    -h, --help            Show this help

ARGUMENTS:
    [TOOL...]             Specific tools to verify (default: all in tools/)

EXAMPLES:
    verify-tools                      # Verify all tools
    verify-tools -o json              # Output results as JSON
    verify-tools scratchpad.sh        # Verify specific tool
    verify-tools --skip-shellcheck    # Skip shellcheck if slow
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

# --- Test Functions ---

record_result() {
    local tool="$1"
    local test_name="$2"
    local status="$3"
    local message="${4:-}"

    results+=("$tool|$test_name|$status|$message")
    ((total_tests++)) || true

    case "$status" in
        pass) ((passed_tests++)) || true ;;
        fail)
            ((failed_tests++)) || true
            issues+=("$tool: $test_name - $message")
            ;;
        skip) ((skipped_tests++)) || true ;;
    esac

    if [[ "$verbose" == true ]]; then
        local symbol
        case "$status" in
            pass) symbol="+" ;;
            fail) symbol="x" ;;
            skip) symbol="-" ;;
        esac
        echo "[$symbol] $tool: $test_name ${message:+- $message}" >&2
    fi
}

test_help() {
    local tool="$1"
    local name
    name=$(basename "$tool")

    log "Testing help for $name"

    local output
    local exit_code=0
    output=$("$tool" -h 2>&1) || exit_code=$?

    # Help should produce output (exit code 1 is expected per template)
    if [[ -n "$output" ]] && echo "$output" | grep -qiE "(usage|options|commands)"; then
        record_result "$name" "help" "pass"
    else
        record_result "$name" "help" "fail" "Missing USAGE/OPTIONS section"
    fi
}

test_json_output() {
    local tool="$1"
    local name
    name=$(basename "$tool")

    log "Testing JSON output for $name"

    # Determine safe read-only command for each tool
    local safe_cmd=""
    case "$name" in
        scratchpad.sh)
            safe_cmd="get"
            ;;
        memory-journal.sh)
            safe_cmd="list"
            ;;
        exa-search.sh)
            # Requires API key - skip
            record_result "$name" "json" "skip" "Requires EXA_API_KEY"
            return
            ;;
        list-tools.sh|verify-tools.sh)
            # Meta-tools - just run without arguments
            safe_cmd=""
            ;;
        *)
            # Unknown tool - try with no args
            record_result "$name" "json" "skip" "No known safe command"
            return
            ;;
    esac

    local output
    local exit_code=0

    if [[ -n "$safe_cmd" ]]; then
        output=$("$tool" -o json "$safe_cmd" 2>/dev/null) || exit_code=$?
    else
        output=$("$tool" -o json 2>/dev/null) || exit_code=$?
    fi

    # Validate JSON with jq
    if echo "$output" | jq . >/dev/null 2>&1; then
        record_result "$name" "json" "pass"
    else
        record_result "$name" "json" "fail" "Invalid JSON output"
    fi
}

test_shellcheck() {
    local tool="$1"
    local name
    name=$(basename "$tool")

    if [[ "$skip_shellcheck" == true ]]; then
        record_result "$name" "shellcheck" "skip" "Skipped by user"
        return
    fi

    if ! command -v shellcheck >/dev/null 2>&1; then
        record_result "$name" "shellcheck" "skip" "shellcheck not installed"
        return
    fi

    log "Running shellcheck on $name"

    local output
    local exit_code=0
    output=$(shellcheck -f gcc "$tool" 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        record_result "$name" "shellcheck" "pass"
    else
        local count
        count=$(echo "$output" | grep -c ":" || echo "0")
        record_result "$name" "shellcheck" "fail" "$count issues found"

        if [[ "$verbose" == true ]]; then
            echo "$output" >&2
        fi
    fi
}

# --- Output Formatters ---

format_json() {
    local timestamp
    timestamp=$(date -Iseconds)

    # Build tools array using jq
    local tools_json="[]"
    local current_tool=""
    local current_tests="{}"

    for result in "${results[@]}"; do
        IFS='|' read -r tool test status message <<< "$result"

        if [[ "$tool" != "$current_tool" ]]; then
            # Save previous tool if exists
            if [[ -n "$current_tool" ]]; then
                tools_json=$(echo "$tools_json" | jq --arg name "$current_tool" --argjson tests "$current_tests" \
                    '. += [{name: $name, tests: $tests}]')
            fi
            current_tool="$tool"
            current_tests="{}"
        fi

        # Add test result
        if [[ -n "$message" ]]; then
            current_tests=$(echo "$current_tests" | jq --arg test "$test" --arg status "$status" --arg msg "$message" \
                '.[$test] = {status: $status, message: $msg}')
        else
            current_tests=$(echo "$current_tests" | jq --arg test "$test" --arg status "$status" \
                '.[$test] = {status: $status}')
        fi
    done

    # Add last tool
    if [[ -n "$current_tool" ]]; then
        tools_json=$(echo "$tools_json" | jq --arg name "$current_tool" --argjson tests "$current_tests" \
            '. += [{name: $name, tests: $tests}]')
    fi

    # Build final output
    jq -n \
        --argjson total "$total_tests" \
        --argjson passed "$passed_tests" \
        --argjson failed "$failed_tests" \
        --argjson skipped "$skipped_tests" \
        --argjson tools "$tools_json" \
        --arg ts "$timestamp" \
        '{
            summary: {
                total_tests: $total,
                passed: $passed,
                failed: $failed,
                skipped: $skipped
            },
            tools: $tools,
            timestamp: $ts
        }'
}

format_markdown() {
    echo "# Tool Verification Report"
    echo ""
    echo "## Summary"
    echo "- Total tests: $total_tests"
    echo "- Passed: $passed_tests"
    echo "- Failed: $failed_tests"
    echo "- Skipped: $skipped_tests"
    echo ""
    echo "## Results"
    echo ""
    echo "| Tool | Help | JSON | Shellcheck | Status |"
    echo "|------|------|------|------------|--------|"

    # Group results by tool
    local -A tool_results
    for result in "${results[@]}"; do
        IFS='|' read -r tool test status message <<< "$result"
        tool_results["$tool,$test"]="$status"
    done

    # Get unique tools
    local -a tools=()
    for result in "${results[@]}"; do
        IFS='|' read -r tool _ _ _ <<< "$result"
        if [[ ! " ${tools[*]} " =~ " $tool " ]]; then
            tools+=("$tool")
        fi
    done

    for tool in "${tools[@]}"; do
        local help_status="${tool_results[$tool,help]:-n/a}"
        local json_status="${tool_results[$tool,json]:-n/a}"
        local sc_status="${tool_results[$tool,shellcheck]:-n/a}"

        local overall="OK"
        if [[ "$help_status" == "fail" || "$json_status" == "fail" || "$sc_status" == "fail" ]]; then
            overall="FAIL"
        fi

        # Format status cells
        local help_cell json_cell sc_cell
        case "$help_status" in
            pass) help_cell="PASS" ;;
            fail) help_cell="FAIL" ;;
            skip) help_cell="SKIP" ;;
            *) help_cell="-" ;;
        esac
        case "$json_status" in
            pass) json_cell="PASS" ;;
            fail) json_cell="FAIL" ;;
            skip) json_cell="SKIP" ;;
            *) json_cell="-" ;;
        esac
        case "$sc_status" in
            pass) sc_cell="PASS" ;;
            fail) sc_cell="FAIL" ;;
            skip) sc_cell="SKIP" ;;
            *) sc_cell="-" ;;
        esac

        echo "| \`$tool\` | $help_cell | $json_cell | $sc_cell | $overall |"
    done

    if [[ ${#issues[@]} -gt 0 ]]; then
        echo ""
        echo "## Issues"
        echo ""
        for issue in "${issues[@]}"; do
            echo "- $issue"
        done
    fi

    echo ""
    echo "---"
    echo "Verified at: $(date -Iseconds)"
}

# --- Main ---

tools_to_verify=()

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
        --skip-shellcheck)
            skip_shellcheck=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            die "unknown option: $1"
            ;;
        *)
            # Tool argument
            if [[ -f "$SCRIPT_DIR/$1" ]]; then
                tools_to_verify+=("$SCRIPT_DIR/$1")
            elif [[ -f "$1" ]]; then
                tools_to_verify+=("$1")
            else
                die "tool not found: $1"
            fi
            shift
            ;;
    esac
done

# Default to all tools if none specified
if [[ ${#tools_to_verify[@]} -eq 0 ]]; then
    for script in "$SCRIPT_DIR"/*.sh; do
        [[ ! -x "$script" ]] && continue
        local_name=$(basename "$script")
        # Skip meta-tools from verification
        [[ "$local_name" == "verify-tools.sh" ]] && continue
        tools_to_verify+=("$script")
    done
fi

log "Verifying ${#tools_to_verify[@]} tools"

# Run tests
for tool in "${tools_to_verify[@]}"; do
    test_help "$tool"
    test_json_output "$tool"
    test_shellcheck "$tool"
done

# Output results
case "$output_format" in
    json)
        format_json
        ;;
    markdown|*)
        format_markdown
        ;;
esac

# Exit with failure if any tests failed
[[ $failed_tests -gt 0 ]] && exit 1
exit 0
