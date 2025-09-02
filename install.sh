#!/bin/bash

# LLM Agent Tools - Smart Installer
# Handles various installation scenarios with data preservation

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEFAULT_CLAUDE_DIR=".claude"
readonly BACKUP_SUFFIX="_backup_$(date +%Y%m%d_%H%M%S)"
readonly VERSION="1.0.0"
readonly VERSION_FILE=".llm-tools-version"

# Directory structure needed
readonly REQUIRED_DIRS=(
    "metadata"
    "code_index"
    "debug_history"
    "patterns"
    "qa"
    "cheatsheets"
    "delta"
    "anchors"
    "scratchpad/active"
    "scratchpad/archive"
    ".rag"
)

# Files to never overwrite
readonly PROTECTED_FILES=(
    "settings.local.json"
    "scratchpad_log.txt"
)

# Installation variables
CLAUDE_DIR=""
INSTALLATION_MODE=""
EXISTING_TYPE=""

# Print functions
print_header() {
    echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}    LLM Agent Tools Installer v${VERSION}${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════${NC}\n"
}

print_status() {
    local color=$1
    local message=$2
    echo -e "${color}●${NC} ${message}"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check bash version
check_bash_version() {
    local bash_version="${BASH_VERSION%%[^0-9.]*}"
    local major_version="${bash_version%%.*}"
    
    if [[ "$major_version" -lt 4 ]]; then
        print_error "Bash version 4.0+ required (found: $bash_version)"
        return 1
    fi
    print_success "Bash version: $bash_version"
    return 0
}

# Check Python version
check_python_version() {
    if ! command_exists python3; then
        print_error "Python 3 not found"
        return 1
    fi
    
    local python_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    local major=$(echo "$python_version" | cut -d. -f1)
    local minor=$(echo "$python_version" | cut -d. -f2)
    
    if [[ "$major" -lt 3 ]] || { [[ "$major" -eq 3 ]] && [[ "$minor" -lt 8 ]]; }; then
        print_error "Python 3.8+ required (found: $python_version)"
        return 1
    fi
    print_success "Python version: $python_version"
    return 0
}

# Check SQLite with FTS5
check_sqlite() {
    if ! command_exists sqlite3; then
        print_error "SQLite3 not found"
        return 1
    fi
    
    if ! sqlite3 ":memory:" "CREATE VIRTUAL TABLE test USING fts5(content);" 2>/dev/null; then
        print_error "SQLite3 without FTS5 support"
        print_info "Install SQLite3 with FTS5 support:"
        print_info "  Ubuntu/Debian: apt install sqlite3"
        print_info "  macOS: brew install sqlite3"
        return 1
    fi
    print_success "SQLite3 with FTS5 support"
    return 0
}

# Check uv package manager
check_uv() {
    if command_exists uv; then
        print_success "uv package manager found"
        return 0
    else
        print_warning "uv package manager not found"
        print_info "uv is recommended for Python dependency management"
        print_info "Install with: curl -LsSf https://astral.sh/uv/install.sh | sh"
        echo -n "Continue without uv? (y/n): "
        read -r response
        [[ "$response" == "y" ]] || [[ "$response" == "Y" ]]
        return $?
    fi
}

# Run dependency checks
check_dependencies() {
    echo -e "\n${BOLD}Checking dependencies...${NC}\n"
    
    local all_good=true
    
    check_bash_version || all_good=false
    check_python_version || all_good=false
    check_sqlite || all_good=false
    check_uv || all_good=false
    
    if [[ "$all_good" == false ]]; then
        echo
        print_error "Some dependencies are missing or outdated"
        echo -n "Continue anyway? (y/n): "
        read -r response
        if [[ "$response" != "y" ]] && [[ "$response" != "Y" ]]; then
            return 1
        fi
    fi
    
    echo
    return 0
}

# Detect existing .claude directory type
detect_claude_type() {
    local dir="$1"
    
    # Check if it's our structure
    if [[ -f "$dir/$VERSION_FILE" ]]; then
        echo "llm-tools"
        return
    fi
    
    # Check for our specific directories
    if [[ -d "$dir/scratchpad" ]] && [[ -d "$dir/metadata" ]] && [[ -d "$dir/patterns" ]]; then
        echo "llm-tools-unversioned"
        return
    fi
    
    # Check for Claude Desktop structure (settings files)
    if [[ -f "$dir/settings.json" ]] || [[ -f "$dir/claude_settings.json" ]]; then
        echo "claude-desktop"
        return
    fi
    
    # Unknown structure
    echo "unknown"
}

# Analyze existing .claude directory
analyze_existing_claude() {
    local dir="$1"
    
    echo -e "\n${BOLD}Analyzing existing $dir directory...${NC}\n"
    
    # Count files and directories
    local file_count=$(find "$dir" -type f 2>/dev/null | wc -l)
    local dir_count=$(find "$dir" -type d 2>/dev/null | wc -l)
    
    print_info "Found $file_count files in $dir_count directories"
    
    # Detect type
    local claude_type=$(detect_claude_type "$dir")
    EXISTING_TYPE="$claude_type"
    
    case "$claude_type" in
        "llm-tools")
            print_success "Detected existing LLM Agent Tools installation"
            if [[ -f "$dir/$VERSION_FILE" ]]; then
                local installed_version=$(cat "$dir/$VERSION_FILE")
                print_info "Installed version: $installed_version"
            fi
            ;;
        "llm-tools-unversioned")
            print_warning "Detected unversioned LLM Agent Tools installation"
            ;;
        "claude-desktop")
            print_warning "Detected Claude Desktop configuration"
            print_info "This appears to be a Claude Desktop settings directory"
            ;;
        "unknown")
            print_warning "Unknown directory structure"
            print_info "Could not identify the purpose of this directory"
            ;;
    esac
    
    # Check for important files
    echo
    print_info "Checking for important files..."
    
    if [[ -f "$dir/settings.local.json" ]]; then
        print_warning "Found settings.local.json - will be preserved"
    fi
    
    if [[ -f "$dir/scratchpad_log.txt" ]]; then
        print_warning "Found scratchpad_log.txt - will be preserved"
    fi
    
    if [[ -d "$dir/.rag" ]] && [[ -f "$dir/.rag/claude_knowledge.db" ]]; then
        local db_size=$(du -h "$dir/.rag/claude_knowledge.db" | cut -f1)
        print_warning "Found existing knowledge database ($db_size) - will be preserved"
    fi
    
    # Check for active scratchpads
    if [[ -d "$dir/scratchpad/active" ]]; then
        local active_count=$(find "$dir/scratchpad/active" -type f 2>/dev/null | wc -l)
        if [[ "$active_count" -gt 0 ]]; then
            print_warning "Found $active_count active scratchpads - will be preserved"
        fi
    fi
    
    echo
}

# Show installation menu
show_installation_menu() {
    echo -e "\n${BOLD}Installation Options:${NC}\n"
    
    if [[ "$EXISTING_TYPE" == "claude-desktop" ]]; then
        print_warning "Detected Claude Desktop configuration"
        echo
        echo "1) Use alternative directory (.llm-agent-tools)"
        echo "2) Backup existing .claude and fresh install"
        echo "3) Cancel installation"
        echo
        echo -n "Select option (1-3): "
    elif [[ "$EXISTING_TYPE" == "llm-tools" ]] || [[ "$EXISTING_TYPE" == "llm-tools-unversioned" ]]; then
        echo "1) Update/repair existing installation (safe merge)"
        echo "2) Backup and fresh install"
        echo "3) Cancel installation"
        echo
        echo -n "Select option (1-3): "
    else
        echo "1) Merge with existing directory (safe, no overwrites)"
        echo "2) Backup existing directory and fresh install"
        echo "3) Use alternative directory (.llm-agent-tools)"
        echo "4) Cancel installation"
        echo
        echo -n "Select option (1-4): "
    fi
    
    read -r choice
    
    case "$EXISTING_TYPE" in
        "claude-desktop")
            case "$choice" in
                1) INSTALLATION_MODE="alternative" ;;
                2) INSTALLATION_MODE="backup" ;;
                3) INSTALLATION_MODE="cancel" ;;
                *) print_error "Invalid choice"; return 1 ;;
            esac
            ;;
        "llm-tools"|"llm-tools-unversioned")
            case "$choice" in
                1) INSTALLATION_MODE="merge" ;;
                2) INSTALLATION_MODE="backup" ;;
                3) INSTALLATION_MODE="cancel" ;;
                *) print_error "Invalid choice"; return 1 ;;
            esac
            ;;
        *)
            case "$choice" in
                1) INSTALLATION_MODE="merge" ;;
                2) INSTALLATION_MODE="backup" ;;
                3) INSTALLATION_MODE="alternative" ;;
                4) INSTALLATION_MODE="cancel" ;;
                *) print_error "Invalid choice"; return 1 ;;
            esac
            ;;
    esac
    
    return 0
}

# Create backup
create_backup() {
    local source="$1"
    local backup="${source}${BACKUP_SUFFIX}"
    
    print_info "Creating backup: $backup"
    
    if ! cp -r "$source" "$backup"; then
        print_error "Failed to create backup"
        return 1
    fi
    
    print_success "Backup created successfully"
    return 0
}

# Create directory structure
create_directory_structure() {
    local base_dir="$1"
    
    for dir in "${REQUIRED_DIRS[@]}"; do
        local full_path="$base_dir/$dir"
        if [[ ! -d "$full_path" ]]; then
            mkdir -p "$full_path"
            print_success "Created: $dir"
        else
            print_info "Exists: $dir"
        fi
    done
}

# Install Python dependencies
install_python_dependencies() {
    echo -e "\n${BOLD}Installing Python dependencies...${NC}\n"
    
    if [[ -f "$SCRIPT_DIR/pyproject.toml" ]]; then
        if command_exists uv; then
            print_info "Installing with uv..."
            cd "$SCRIPT_DIR"
            uv pip install -r pyproject.toml
            print_success "Python dependencies installed"
        else
            print_warning "Installing with pip..."
            cd "$SCRIPT_DIR"
            python3 -m pip install --user pyyaml
            print_success "Basic Python dependencies installed"
        fi
    else
        print_warning "pyproject.toml not found, skipping Python dependencies"
    fi
}

# Copy example files
copy_example_files() {
    local target_dir="$1"
    
    # Create README if it doesn't exist
    if [[ ! -f "$target_dir/README.md" ]]; then
        cat > "$target_dir/README.md" << 'EOF'
# Claude Knowledge Base

This directory contains your personal knowledge base for LLM Agent Tools.

## Directory Structure

- `metadata/` - System architecture, component relationships
- `code_index/` - Code relationships, function mappings
- `debug_history/` - Debugging sessions and solutions
- `patterns/` - Reusable patterns and best practices
- `qa/` - Questions answered with explanations
- `cheatsheets/` - Quick references and shortcuts
- `delta/` - Change logs and updates
- `anchors/` - Important code locations
- `scratchpad/` - Temporary working notes

## Usage

Files in this directory are indexed by the RAG system for quick retrieval.
Run `./claude-rag-lite.sh build` to update the search index after adding new files.
EOF
        print_success "Created README.md"
    fi
    
    # Create version file
    echo "$VERSION" > "$target_dir/$VERSION_FILE"
    print_success "Created version file"
}

# Update scripts for configurable paths
update_scripts() {
    local use_custom_dir="$1"
    
    echo -e "\n${BOLD}Updating scripts...${NC}\n"
    
    # Create config file if using custom directory
    if [[ "$use_custom_dir" == "true" ]]; then
        cat > "$SCRIPT_DIR/.llm-tools.conf" << EOF
# LLM Agent Tools Configuration
# This file is automatically sourced by the scripts

# Custom Claude directory path
export CLAUDE_DIR="$CLAUDE_DIR"

# Other configuration options can be added here
EOF
        print_success "Created configuration file: .llm-tools.conf"
    fi
    
    # Make scripts executable
    chmod +x "$SCRIPT_DIR/scratchpad.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR/claude-rag-lite.sh" 2>/dev/null || true
    
    print_success "Scripts updated"
}

# Create uninstall script
create_uninstall_script() {
    local target_dir="$1"
    
    cat > "$SCRIPT_DIR/uninstall.sh" << EOF
#!/bin/bash

# LLM Agent Tools Uninstaller
# Created by installer on $(date)

set -euo pipefail

readonly RED='\\033[0;31m'
readonly GREEN='\\033[0;32m'
readonly YELLOW='\\033[1;33m'
readonly NC='\\033[0m'

echo -e "\\n\${YELLOW}LLM Agent Tools Uninstaller\${NC}\\n"

echo "This will remove LLM Agent Tools from your system."
echo "Your knowledge base and scratchpads will be preserved."
echo
echo -n "Continue? (y/n): "
read -r response

if [[ "\$response" != "y" ]] && [[ "\$response" != "Y" ]]; then
    echo "Uninstall cancelled"
    exit 0
fi

# Remove version file
if [[ -f "$target_dir/$VERSION_FILE" ]]; then
    rm "$target_dir/$VERSION_FILE"
    echo -e "\${GREEN}✓\${NC} Removed version file"
fi

# Remove config file
if [[ -f "$SCRIPT_DIR/.llm-tools.conf" ]]; then
    rm "$SCRIPT_DIR/.llm-tools.conf"
    echo -e "\${GREEN}✓\${NC} Removed configuration file"
fi

# Ask about knowledge base
echo
echo -n "Remove knowledge base directory '$target_dir'? (y/n): "
read -r response

if [[ "\$response" == "y" ]] || [[ "\$response" == "Y" ]]; then
    echo -n "Create backup first? (y/n): "
    read -r backup_response
    
    if [[ "\$backup_response" == "y" ]] || [[ "\$backup_response" == "Y" ]]; then
        backup_dir="${target_dir}_uninstall_backup_\$(date +%Y%m%d_%H%M%S)"
        cp -r "$target_dir" "\$backup_dir"
        echo -e "\${GREEN}✓\${NC} Backup created: \$backup_dir"
    fi
    
    rm -rf "$target_dir"
    echo -e "\${GREEN}✓\${NC} Removed knowledge base directory"
else
    echo -e "\${YELLOW}⚠\${NC} Knowledge base preserved"
fi

echo
echo -e "\${GREEN}Uninstall complete!\${NC}"
echo
echo "Note: The script files themselves were not removed."
echo "You can manually delete the installation directory if desired."
EOF
    
    chmod +x "$SCRIPT_DIR/uninstall.sh"
    print_success "Created uninstall script"
}

# Run installation
run_installation() {
    case "$INSTALLATION_MODE" in
        "fresh")
            echo -e "\n${BOLD}Running fresh installation...${NC}\n"
            CLAUDE_DIR="$SCRIPT_DIR/$DEFAULT_CLAUDE_DIR"
            create_directory_structure "$CLAUDE_DIR"
            copy_example_files "$CLAUDE_DIR"
            update_scripts "false"
            ;;
            
        "merge")
            echo -e "\n${BOLD}Running safe merge installation...${NC}\n"
            CLAUDE_DIR="$SCRIPT_DIR/$DEFAULT_CLAUDE_DIR"
            create_directory_structure "$CLAUDE_DIR"
            copy_example_files "$CLAUDE_DIR"
            update_scripts "false"
            ;;
            
        "backup")
            echo -e "\n${BOLD}Running backup and fresh install...${NC}\n"
            CLAUDE_DIR="$SCRIPT_DIR/$DEFAULT_CLAUDE_DIR"
            create_backup "$CLAUDE_DIR"
            rm -rf "$CLAUDE_DIR"
            create_directory_structure "$CLAUDE_DIR"
            copy_example_files "$CLAUDE_DIR"
            update_scripts "false"
            ;;
            
        "alternative")
            echo -e "\n${BOLD}Installing with alternative directory...${NC}\n"
            CLAUDE_DIR="$SCRIPT_DIR/.llm-agent-tools"
            create_directory_structure "$CLAUDE_DIR"
            copy_example_files "$CLAUDE_DIR"
            update_scripts "true"
            ;;
            
        "cancel")
            print_info "Installation cancelled"
            exit 0
            ;;
            
        *)
            print_error "Unknown installation mode: $INSTALLATION_MODE"
            exit 1
            ;;
    esac
    
    # Install Python dependencies
    install_python_dependencies
    
    # Create uninstall script
    create_uninstall_script "$CLAUDE_DIR"
}

# Post-installation instructions
show_post_install() {
    echo -e "\n${BOLD}${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}    Installation Complete!${NC}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════${NC}\n"
    
    if [[ "$INSTALLATION_MODE" == "alternative" ]]; then
        print_info "Using alternative directory: $CLAUDE_DIR"
        print_info "Configuration saved to: .llm-tools.conf"
        echo
    fi
    
    echo -e "${BOLD}Quick Start:${NC}\n"
    echo "1. Create a new scratchpad:"
    echo "   ./scratchpad.sh new task 'my_first_task'"
    echo
    echo "2. Build the knowledge base index:"
    echo "   ./claude-rag-lite.sh build"
    echo
    echo "3. Search the knowledge base:"
    echo "   ./claude-rag-lite.sh query 'search terms'"
    echo
    
    if [[ -f "$SCRIPT_DIR/uninstall.sh" ]]; then
        print_info "To uninstall, run: ./uninstall.sh"
    fi
    
    echo
    print_success "Happy coding with LLM Agent Tools!"
}

# Main installation flow
main() {
    print_header
    
    # Check dependencies
    if ! check_dependencies; then
        print_error "Installation aborted due to missing dependencies"
        exit 1
    fi
    
    # Check for existing .claude directory
    if [[ -d "$SCRIPT_DIR/$DEFAULT_CLAUDE_DIR" ]]; then
        analyze_existing_claude "$SCRIPT_DIR/$DEFAULT_CLAUDE_DIR"
        
        if ! show_installation_menu; then
            print_error "Installation aborted"
            exit 1
        fi
    else
        # Fresh installation
        print_info "No existing $DEFAULT_CLAUDE_DIR directory found"
        INSTALLATION_MODE="fresh"
    fi
    
    # Run the installation
    run_installation
    
    # Show completion message
    show_post_install
}

# Run main function
main "$@"