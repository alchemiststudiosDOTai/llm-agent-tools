#!/bin/bash

# LLM Agent Tools Uninstaller
# Created by installer on Tue Sep  2 12:18:12 CDT 2025

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

echo -e "\n${YELLOW}LLM Agent Tools Uninstaller${NC}\n"

echo "This will remove LLM Agent Tools from your system."
echo "Your knowledge base and scratchpads will be preserved."
echo
echo -n "Continue? (y/n): "
read -r response

if [[ "$response" != "y" ]] && [[ "$response" != "Y" ]]; then
    echo "Uninstall cancelled"
    exit 0
fi

# Remove version file
if [[ -f "/home/fabian/tunacode-sythetic-generation/llm-agent-tools/.claude/.llm-tools-version" ]]; then
    rm "/home/fabian/tunacode-sythetic-generation/llm-agent-tools/.claude/.llm-tools-version"
    echo -e "${GREEN}✓${NC} Removed version file"
fi

# Remove config file
if [[ -f "/home/fabian/tunacode-sythetic-generation/llm-agent-tools/.llm-tools.conf" ]]; then
    rm "/home/fabian/tunacode-sythetic-generation/llm-agent-tools/.llm-tools.conf"
    echo -e "${GREEN}✓${NC} Removed configuration file"
fi

# Ask about knowledge base
echo
echo -n "Remove knowledge base directory '/home/fabian/tunacode-sythetic-generation/llm-agent-tools/.claude'? (y/n): "
read -r response

if [[ "$response" == "y" ]] || [[ "$response" == "Y" ]]; then
    echo -n "Create backup first? (y/n): "
    read -r backup_response
    
    if [[ "$backup_response" == "y" ]] || [[ "$backup_response" == "Y" ]]; then
        backup_dir="/home/fabian/tunacode-sythetic-generation/llm-agent-tools/.claude_uninstall_backup_$(date +%Y%m%d_%H%M%S)"
        cp -r "/home/fabian/tunacode-sythetic-generation/llm-agent-tools/.claude" "$backup_dir"
        echo -e "${GREEN}✓${NC} Backup created: $backup_dir"
    fi
    
    rm -rf "/home/fabian/tunacode-sythetic-generation/llm-agent-tools/.claude"
    echo -e "${GREEN}✓${NC} Removed knowledge base directory"
else
    echo -e "${YELLOW}⚠${NC} Knowledge base preserved"
fi

echo
echo -e "${GREEN}Uninstall complete!${NC}"
echo
echo "Note: The script files themselves were not removed."
echo "You can manually delete the installation directory if desired."
