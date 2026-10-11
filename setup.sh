#!/bin/bash

# MacDown 3000 Development Environment Setup Script
# This script automates the setup process for developers

set -e  # Exit on error

echo "======================================"
echo "MacDown 3000 Development Setup"
echo "======================================"
echo ""

# Check if we're in the right directory
if [ ! -f "MacDown 3000.xcodeproj/project.pbxproj" ]; then
    echo "Error: This script must be run from the MacDown 3000 project root directory"
    exit 1
fi

# Step 1: Initialize git submodules
echo "[1/5] Initializing git submodules..."
git submodule update --init --recursive
echo "✓ Submodules initialized"
echo ""

# Step 2: Install Ruby dependencies
echo "[2/5] Installing Ruby dependencies with Bundler..."
if ! command -v bundle &> /dev/null; then
    echo "Error: Bundler is not installed. Please install it with: gem install bundler"
    exit 1
fi
bundle install
echo "✓ Ruby dependencies installed"
echo ""

# Step 3: Install CocoaPods dependencies
echo "[3/5] Installing CocoaPods dependencies..."
bundle exec pod install
echo "✓ CocoaPods dependencies installed"
echo ""

# Step 4: Build peg-markdown-highlight
echo "[4/5] Building peg-markdown-highlight..."
make -C Dependency/peg-markdown-highlight
echo "✓ peg-markdown-highlight built successfully"
echo ""

# Step 5: Install the pinned CSS generator dependencies. Xcode generates styles
# in its shared resource target and fails if the Sass executable is absent.
echo "[5/5] Installing CSS generator dependencies..."
if ! command -v npm &> /dev/null || ! command -v node &> /dev/null; then
    echo "Error: Node.js 20.19 or newer and npm are required" >&2
    exit 1
fi
node -e 'const [major, minor] = process.versions.node.split(".").map(Number); if (major < 20 || (major === 20 && minor < 19)) process.exit(1)' || {
    echo "Error: Node.js 20.19 or newer is required by the pinned Sass version" >&2
    exit 1
}
npm ci --prefix Tools/GitHub-style-generator --ignore-scripts --no-audit --no-fund
echo "✓ CSS generator dependencies installed"
echo ""

echo "======================================"
echo "✓ Setup complete!"
echo "======================================"
echo ""
echo "Next steps:"
echo "  1. Open \"MacDown 3000.xcworkspace\" in Xcode"
echo "  2. Select the MacDown scheme"
echo "  3. Build and run (Cmd+R)"
echo ""
echo "To run tests:"
echo "  xcodebuild test -workspace \"MacDown 3000.xcworkspace\" -scheme MacDown"
echo ""
