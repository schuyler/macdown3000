#!/bin/bash
#
# Duck Soup Plugin Installation Script
# - Installs the duck-soup development workflow plugin if not already present
# - Provides a comprehensive development workflow with quality gates
# - Includes specialized agents: Groucho, Chico, Zeppo, Harpo
#

echo "=== Duck Soup Plugin Setup ==="
echo ""

# Check if plugin is already installed
PLUGIN_DIR=".claude/plugins/dev"

if [ -d "$PLUGIN_DIR" ] && [ -f "$PLUGIN_DIR/.claude-plugin/plugin.json" ]; then
  echo "✓ Duck Soup plugin already installed at $PLUGIN_DIR"

  # Show plugin version if available
  if command -v python3 >/dev/null 2>&1; then
    VERSION=$(python3 -c "
import json, sys
try:
    with open('$PLUGIN_DIR/.claude-plugin/plugin.json', 'r') as f:
        data = json.load(f)
        version = data.get('version', 'unknown')
        print(version)
except:
    print('unknown')
" 2>/dev/null)
    if [ -n "$VERSION" ] && [ "$VERSION" != "unknown" ]; then
      echo "  Version: $VERSION"
    fi
  fi
else
  echo "📦 Installing Duck Soup plugin..."

  # Create plugins directory if it doesn't exist
  mkdir -p .claude/plugins

  # Clone the plugin repository
  if git clone https://github.com/schuyler/duck-soup.git "$PLUGIN_DIR" >/dev/null 2>&1; then
    # Remove the nested .git directory to avoid submodule issues
    rm -rf "$PLUGIN_DIR/.git"

    echo "✓ Duck Soup plugin installed successfully"

    # Show plugin version
    if command -v python3 >/dev/null 2>&1 && [ -f "$PLUGIN_DIR/.claude-plugin/plugin.json" ]; then
      VERSION=$(python3 -c "
import json, sys
try:
    with open('$PLUGIN_DIR/.claude-plugin/plugin.json', 'r') as f:
        data = json.load(f)
        version = data.get('version', 'unknown')
        print(version)
except:
    print('unknown')
" 2>/dev/null)
      if [ -n "$VERSION" ] && [ "$VERSION" != "unknown" ]; then
        echo "  Version: $VERSION"
      fi
    fi
  else
    echo "⚠ Failed to clone Duck Soup plugin"
    echo "  Repository: https://github.com/schuyler/duck-soup"
    exit 1
  fi
fi

echo ""
echo "Duck Soup Usage:"
echo "  /dev:start <task description>   # Start structured development workflow"
echo ""
echo "Example:"
echo "  /dev:start Add user authentication with JWT tokens"
echo ""
echo "The workflow includes 7 phases:"
echo "  1. Requirements gathering (Groucho - architect)"
echo "  2. Planning"
echo "  3. Implementation"
echo "  4. Code review (Chico - reviewer)"
echo "  5. Verification (Zeppo - debugger)"
echo "  6. Documentation (Harpo - documentation)"
echo "  7. Reflection"
echo ""
