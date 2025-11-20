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
echo "[1/4] Initializing git submodules..."
git submodule update --init --recursive
echo "✓ Submodules initialized"
echo ""

# Step 2: Install Ruby dependencies
echo "[2/4] Installing Ruby dependencies with Bundler..."
if ! command -v bundle &> /dev/null; then
    echo "Error: Bundler is not installed. Please install it with: gem install bundler"
    exit 1
fi
bundle install
echo "✓ Ruby dependencies installed"
echo ""

# Step 3: Install CocoaPods dependencies
echo "[3/4] Installing CocoaPods dependencies..."
bundle exec pod install
echo "✓ CocoaPods dependencies installed"
echo ""

# Step 4: Build peg-markdown-highlight
echo "[4/4] Building peg-markdown-highlight..."
make -C Dependency/peg-markdown-highlight
echo "✓ peg-markdown-highlight built successfully"
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
