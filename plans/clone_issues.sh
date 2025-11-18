#!/bin/bash

# Script to clone top 20 MacDown bug issues to this repository
# Usage: ./clone_issues.sh <GITHUB_TOKEN>

if [ -z "$1" ]; then
    echo "Error: GitHub token required"
    echo "Usage: $0 <GITHUB_TOKEN>"
    echo ""
    echo "Create a token at: https://github.com/settings/tokens"
    echo "Required scope: repo"
    exit 1
fi

GITHUB_TOKEN="$1"
REPO_OWNER="schuyler"
REPO_NAME="macdown3000"
ORIGINAL_REPO="MacDownApp/macdown"

# Issue data: number|title|body|comments
declare -a ISSUES=(
    "1104|Rendering pane flashing|Preview pane flashes on nearly every keystroke after upgrading to 0.7.2, occurring across multiple theme and syntax highlighting combinations.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/1104 (77 comments)|77"
    "1057|Preview pane flickers when typing/updating|Flickering in preview pane occurs with every keystroke, referencing a similar bug (#253) on macOS Mojave 10.14.3.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/1057 (16 comments)|16"
    "892|Code formatting not respecting indentation|Indentation in code blocks not preserved correctly; renders differently than GitHub.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/892 (13 comments)|13"
    "1133|Drag and drop text|Drag and drop text functionality stopped working in version 0.7.2, though it worked in 0.7.1.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/1133 (12 comments)|12"
    "1051|Build failed in Xcode 10.1|Build cycle error with Pods Frameworks embedding and copy commands.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/1051 (12 comments)|12"
    "788|Opening large files causes editor to white screen|Large markdown files cause editor to display blank after saving and reopening; preview pane functions normally.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/788 (10 comments)|10"
    "716|Crash when scrolling on initial Markdown preview render (MacOS Sierra)|Application crashes when scrolling preview before rendering completes on large files.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/716 (7 comments)|7"
    "700|\`(*) *BOLD* text\` renders wrong in code-pane|Specific markdown syntax with bullets and bold text renders incorrectly.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/700 (7 comments)|7"
    "817|Does not print or generate correctly when Preview Pane is hidden|PDF export and printing don't include new content when preview pane is hidden.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/817 (6 comments)|6"
    "820|A name tags are broken under 10.13 (17A264c)|Named anchor tags malfunction on macOS High Sierra.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/820 (5 comments)|5"
    "1157|Mermaid issue on latest release 0.8.0d71|Reports that the today's indicator line disappears in gantt diagrams when date format isn't set, and x-axis date display overlaps.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/1157 (4 comments)|4"
    "1138|Graphviz's filled and color attributes doesn't work|Graphviz node styling with \`style=filled\` and \`color\` attributes fails to render properly. Issue traced to an older Mermaid version with CSS overrides.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/1138 (4 comments)|4"
    "1072|When xCode is compiled, this error is prompted, how to solve it?|Compilation error when building with Xcode (includes screenshot reference).\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/1072 (4 comments)|4"
    "1060|Render newline literally doesn't work randomly|The \"Render newline literally\" option works intermittently. Disabling and re-enabling fixes it temporarily, but the problem recurs after closing/reopening files.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/1060 (4 comments)|4"
    "1004|German version instead of french?|Application displays in German rather than French despite user's system language preference.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/1004 (4 comments)|4"
    "753|Hiding both editor and preview panes bug|Hiding both panes simultaneously allows only one to be visible; normal pane restoration unavailable without menu intervention.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/753 (4 comments)|4"
    "725|New file behavior is a bit confusing|Creating new files via markdown links displays error message and locks editor until file is saved empty first.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/725 (4 comments)|4"
    "1048|Trouble with two shortcut links side by side|Two adjacent shortcut-style links fail to render correctly in MacDown preview compared to GitHub's rendering.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/1048 (3 comments)|3"
    "903|Wrong ordered list index in specific situation|Ordered list numbering resets incorrectly when text separates list items.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/903 (3 comments)|3"
    "860|Multiple, separated quotes rendered as the same quote|Multiple blockquotes separated by blank lines combine into a single blockquote instead of remaining separate.\n\nOriginal issue: https://github.com/${ORIGINAL_REPO}/issues/860 (3 comments)|3"
)

echo "Creating ${#ISSUES[@]} issues in ${REPO_OWNER}/${REPO_NAME}..."
echo ""

for issue_data in "${ISSUES[@]}"; do
    IFS='|' read -r issue_num title body comments <<< "$issue_data"

    echo "Creating issue: #${issue_num} - ${title}"

    # Create the issue using GitHub API
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues" \
        -d "{\"title\":\"${title}\",\"body\":$(echo -e "${body}" | jq -Rs .),\"labels\":[\"bug\",\"cloned-issue\"]}")

    http_code=$(echo "$response" | tail -n1)
    response_body=$(echo "$response" | head -n-1)

    if [ "$http_code" = "201" ]; then
        new_issue_num=$(echo "$response_body" | jq -r '.number')
        echo "  ✓ Created as issue #${new_issue_num}"
    else
        echo "  ✗ Failed (HTTP ${http_code})"
        echo "  Error: $(echo "$response_body" | jq -r '.message // "Unknown error"')"
    fi

    # Rate limiting: sleep briefly between requests
    sleep 1
done

echo ""
echo "Done!"
