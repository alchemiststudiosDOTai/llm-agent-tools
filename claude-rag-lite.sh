#!/bin/bash

# claude-rag-lite.sh
# Compact SQLite FTS5-based RAG system for .claude knowledge base

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CLAUDE_DIR="${SCRIPT_DIR}/.claude"
readonly DB_PATH="${CLAUDE_DIR}/.rag/claude_knowledge.db"
readonly PYTHON_SCRIPTS="${SCRIPT_DIR}/rag_modules"
readonly MAX_SNIPPET_LENGTH="${MAX_SNIPPET_LENGTH:-500}"
readonly DEFAULT_LIMIT="${DEFAULT_LIMIT:-10}"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date +"%H:%M:%S")]${NC} ${message}"
}

# Function to ensure .claude directory structure exists
ensure_claude_dir() {
    if [[ ! -d "${CLAUDE_DIR}" ]]; then
        print_status "${YELLOW}" "Creating .claude directory structure..."
        mkdir -p "${CLAUDE_DIR}"/{metadata,code_index,debug_history,patterns,qa,cheatsheets,delta,anchors,scratchpad/{active,archive}}
        mkdir -p "${CLAUDE_DIR}/.rag"
        print_status "${GREEN}" "Created .claude directory structure"
    fi
    
    if [[ ! -d "${CLAUDE_DIR}/.rag" ]]; then
        mkdir -p "${CLAUDE_DIR}/.rag"
    fi
}

# Function to setup Python environment with uv
setup_python_env() {
    if [[ ! -d "${PYTHON_SCRIPTS}" ]]; then
        mkdir -p "${PYTHON_SCRIPTS}"
    fi
    
    # Check if uv is installed
    if ! command -v uv &> /dev/null; then
        print_status "${RED}" "uv is not installed. Please install it first:"
        echo "curl -LsSf https://astral.sh/uv/install.sh | sh"
        exit 1
    fi
    
    # Create pyproject.toml if it doesn't exist
    if [[ ! -f "${SCRIPT_DIR}/pyproject.toml" ]]; then
        cat > "${SCRIPT_DIR}/pyproject.toml" << 'EOF'
[project]
name = "claude-rag-lite"
version = "0.1.0"
requires-python = ">=3.9"
dependencies = []

[tool.uv]
dev-dependencies = []
EOF
        print_status "${GREEN}" "Created pyproject.toml"
    fi
    
    # Initialize venv if it doesn't exist
    if [[ ! -d "${SCRIPT_DIR}/.venv" ]]; then
        print_status "${YELLOW}" "Creating Python virtual environment with uv..."
        cd "${SCRIPT_DIR}"
        uv venv
        print_status "${GREEN}" "Virtual environment created"
    fi
    
    # No additional packages needed - using stdlib only
    print_status "${CYAN}" "Python environment ready (using stdlib only)"
}

# Function to build/update the FTS5 index
build_index() {
    ensure_claude_dir
    setup_python_env
    
    print_status "${CYAN}" "Building/updating FTS5 index..."
    
    # Run the indexer Python script
    cd "${SCRIPT_DIR}"
    uv run python3 "${PYTHON_SCRIPTS}/indexer.py" \
        --claude-dir "${CLAUDE_DIR}" \
        --db-path "${DB_PATH}" \
        --incremental
    
    # Show statistics
    local doc_count=$(uv run python3 -c "
import sqlite3
conn = sqlite3.connect('${DB_PATH}')
cursor = conn.cursor()
cursor.execute('SELECT COUNT(*) FROM docs')
count = cursor.fetchone()[0]
conn.close()
print(count)
" 2>/dev/null || echo "0")
    
    print_status "${GREEN}" "Index updated. Total documents: ${doc_count}"
}

# Function to query the index
query_index() {
    local query="$1"
    local limit="${2:-${DEFAULT_LIMIT}}"
    local format="${3:-json}"
    
    if [[ ! -f "${DB_PATH}" ]]; then
        print_status "${RED}" "Index not found. Run '$(basename $0) build' first."
        exit 1
    fi
    
    # Run the search Python script
    cd "${SCRIPT_DIR}"
    uv run python3 "${PYTHON_SCRIPTS}/search.py" \
        --db-path "${DB_PATH}" \
        --query "${query}" \
        --limit "${limit}" \
        --max-snippet "${MAX_SNIPPET_LENGTH}" \
        --format "${format}"
}

# Function to show index statistics
show_stats() {
    if [[ ! -f "${DB_PATH}" ]]; then
        print_status "${RED}" "Index not found. Run '$(basename $0) build' first."
        exit 1
    fi
    
    cd "${SCRIPT_DIR}"
    uv run python3 "${PYTHON_SCRIPTS}/stats.py" --db-path "${DB_PATH}"
}

# Function to reset the index
reset_index() {
    read -p "Are you sure you want to reset the index? This will delete all indexed data. (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "${DB_PATH}"
        print_status "${GREEN}" "Index reset complete"
    else
        print_status "${YELLOW}" "Reset cancelled"
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Claude RAG Lite - Compact SQLite FTS5 RAG System

Usage: $(basename "$0") [command] [options]

Commands:
  build                       Build or update the FTS5 index incrementally
  
  query <search_term> [limit] [format]
                             Search the index
                             - limit: max results (default: ${DEFAULT_LIMIT})
                             - format: json|text|markdown (default: json)
  
  stats                      Show index statistics
  
  reset                      Reset the index (delete all data)
  
  help                       Show this help message

Examples:
  $(basename "$0") build
  $(basename "$0") query "authentication" 5
  $(basename "$0") query "error handling" 10 text
  $(basename "$0") query "async pattern" 15 markdown
  $(basename "$0") stats

Environment Variables:
  MAX_SNIPPET_LENGTH         Maximum snippet length (default: 500)
  DEFAULT_LIMIT             Default result limit (default: 10)

Output Formats:
  json                      Compact JSONL format for agent consumption
  text                      Human-readable text format
  markdown                  Formatted markdown with highlights

EOF
}

# Main function
main() {
    local command="${1:-help}"
    shift || true
    
    case "${command}" in
        build)
            build_index
            ;;
            
        query)
            if [[ -z "${1:-}" ]]; then
                print_status "${RED}" "Error: search query required"
                exit 1
            fi
            query_index "$@"
            ;;
            
        stats)
            show_stats
            ;;
            
        reset)
            reset_index
            ;;
            
        help)
            show_usage
            ;;
            
        *)
            print_status "${RED}" "Unknown command: ${command}"
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"