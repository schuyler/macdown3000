#!/bin/bash
# Initialize a new feature implementation session directory
# Usage: ./init_session.sh <feature-slug>

set -e

if [ -z "$1" ]; then
    echo "Error: Feature slug required"
    echo "Usage: $0 <feature-slug>"
    exit 1
fi

SLUG="$1"
TIMESTAMP=$(date +"%Y%m%d")
SESSION_DIR="docs/sessions/${TIMESTAMP}-${SLUG}"

# Create session directory
mkdir -p "$SESSION_DIR"

echo "✅ Session initialized: $SESSION_DIR"
