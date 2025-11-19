# MacDown 3000 Label System Guide

**Created:** 2025-11-18
**Last Updated:** 2025-11-19
**Purpose:** Standardized issue categorization and tracking

---

## 🏷️ Label Categories

### 1. Type (What kind of issue?)

- `bug` - Something isn't working correctly (38 issues)
- `enhancement` - New feature or improvement (30 issues)
- `documentation` - Improvements or additions to documentation (6 issues)
- `question` - Further information is requested (1 issue)

### 2. Priority (How urgent?)

- `critical` - Blocking release, security issue, data loss (7 issues)
- `high` - Important for release, significant impact (22 issues)
- `medium` - Should do, moderate impact (25 issues)
- `low` - Nice to have, minor impact (7 issues)

### 3. Component/Area (Which part of the application?)

- `rendering` - Markdown/HTML/LaTeX rendering (14 issues)
- `editor` - Text editor pane (5 issues)
- `preview` - Preview pane functionality (5 issues)
- `export` - PDF/HTML export (6 issues)
- `ui` - User interface, windows, menus (2 issues)
- `preferences` - Settings and preferences (3 issues)
- `file-io` - File operations, autosave (4 issues)
- `diagrams` - Mermaid/Graphviz diagram rendering (4 issues)
- `syntax` - Syntax highlighting (1 issue)

### 4. Technology/Infrastructure

- `build` - Build system, Xcode configuration (12 issues)
- `dependencies` - Pull requests that update dependencies (7 issues)
- `ci-cd` or `ci/cd` - GitHub Actions, CI/CD workflows (6 + 1 issues)
- `testing` - Testing infrastructure and test cases (25 issues)
- `infrastructure` - Build, CI/CD, project infrastructure (21 issues)
- `code-signing` - Code signing and notarization (1 issue)
- `localization` - Internationalization and translations (2 issues)
- `security` - Security issues and improvements (2 issues)

### 5. Special Technical

- `hoedown` - Related to Hoedown Markdown parser (8 issues)
- `markdown-parsing` - Markdown parsing issues (1 issue)
- `javascript` - JavaScript-related updates (1 issue)
- `cli` - Command-line tool (1 issue)

### 6. Status/Workflow

- `backlog` - Not scheduled yet (3 issues)
- `good-first-issue` - Good for newcomers (2 issues)
- `help-wanted` - Extra attention needed (1 issue)
- `upstream` - Issue in a dependency, not our code (1 issue)

### 7. Milestone/Release

- `v0.1` - Must have for v0.1 release (27 issues)

### 8. Source/Origin

- `cloned-issue` - Cloned from original MacDown repository (34 issues)
- `cloned-pr` - Based on original MacDown PR (4 issues)

---

## 🎯 Usage Guidelines

### For Contributors

**Finding Work:**

```
Good first issues:
  - Filter: label:"good-first-issue"
  - Small, well-defined tasks perfect for getting started

Help wanted:
  - Filter: label:"help-wanted"
  - Issues needing extra attention

By component:
  - Filter: label:"rendering"
  - Focus on specific area of the codebase

By priority and size:
  - Filter: label:"medium" label:"good-first-issue"
  - Medium priority tasks good for newcomers
```

**Issue Triage Process:**

1. Apply type label: `bug`, `enhancement`, `documentation`, etc.
2. Apply priority label: `critical`, `high`, `medium`, or `low`
3. Apply component labels as appropriate: `rendering`, `editor`, `preview`, etc.
4. Apply milestone label if release-critical: `v0.1` or `backlog`
5. Apply special labels if needed: `good-first-issue`, `help-wanted`, etc.
6. Apply source label if from upstream: `cloned-issue` or `cloned-pr`

### For Maintainers

**Planning v0.1 Release:**

```
Critical path:
  - Filter: label:"v0.1" label:"critical"
  - Must be done before v0.1 release

High priority v0.1:
  - Filter: label:"v0.1" label:"high"
  - Important for v0.1 quality

All v0.1 issues:
  - Filter: label:"v0.1"
  - 27 total issues targeted for first release
```

**By Technology Area:**

```
Testing infrastructure:
  - Filter: label:"testing"
  - 25 issues improving test coverage

Build and infrastructure:
  - Filter: label:"infrastructure"
  - 21 issues for build system, CI/CD

Dependencies to update:
  - Filter: label:"dependencies"
  - 7 dependency-related issues

CI/CD improvements:
  - Filter: label:"ci-cd" OR label:"ci/cd"
  - Workflow and automation improvements
```

**By Component:**

```
Rendering issues:
  - Filter: label:"rendering"
  - 14 issues with Markdown/HTML/LaTeX rendering

Editor improvements:
  - Filter: label:"editor"
  - 5 issues with text editor pane

Preview pane:
  - Filter: label:"preview"
  - 5 issues with preview functionality
```

---

## 📈 Current Project State

**Total Issues:** 114 (open and closed)

**Label Statistics:**
- Most common type: `bug` (38 issues)
- Most common priority: `medium` (25 issues)
- Most common component: `rendering` (14 issues)
- Release targeted: `v0.1` (27 issues)
- From upstream: `cloned-issue` (34 issues)

**Use GitHub's issue filters to view current state:**
- **Release Blockers:** `label:"critical" is:open`
- **v0.1 Milestone:** `label:"v0.1" is:open`
- **Quick Wins:** `label:"good-first-issue" is:open`
- **Help Wanted:** `label:"help-wanted" is:open`

---

## 🔍 Useful Filters

### For Contributors

- **Easy wins:** `label:"good-first-issue" is:open`
- **Documentation:** `label:"documentation" is:open`
- **Bugs to fix:** `label:"bug" is:open`
- **New features:** `label:"enhancement" is:open`
- **Rendering work:** `label:"rendering" is:open`
- **Editor work:** `label:"editor" is:open`

### For Project Management

- **This week:** `label:"v0.1" label:"critical" is:open`
- **Next sprint:** `label:"v0.1" label:"high" is:open`
- **Backlog:** `label:"backlog" is:open`
- **All v0.1 work:** `label:"v0.1" is:open`

### For Quality Assurance

- **Security issues:** `label:"security" is:open`
- **Critical bugs:** `label:"bug" label:"critical" is:open`
- **Testing gaps:** `label:"testing" is:open`
- **High priority bugs:** `label:"bug" label:"high" is:open`

### For Infrastructure Work

- **Build system:** `label:"build" is:open`
- **CI/CD:** `label:"ci-cd" is:open OR label:"ci/cd" is:open`
- **Dependencies:** `label:"dependencies" is:open`
- **Infrastructure:** `label:"infrastructure" is:open`

---

## 📝 Label Maintenance

### Cleanup History

**2025-11-19:** Major label cleanup
- Replaced `priority: {x}` prefix labels with `{x}` (removed redundant prefix)
- Restored 11 orphaned labels that were in use but missing from repository
- Deleted 25 unused labels
- Result: 37 labels, all actively in use

### Adding New Labels

If you need a new label:

1. Check if an existing label fits the purpose
2. Discuss in an issue or PR first
3. Choose a clear, concise name (avoid prefixes unless necessary)
4. Add an appropriate description
5. Choose a color that fits with similar labels
6. Update this guide after creating the label

### Label Naming Conventions

- Use lowercase with hyphens: `good-first-issue`, not `GoodFirstIssue`
- Be descriptive but concise: `rendering`, not `rendering-related-issues`
- Avoid redundant prefixes unless they add clarity
- Use existing labels when possible before creating new ones

### Modifying Labels

Labels can be edited at:
https://github.com/schuyler/macdown3000/labels

Keep colors consistent within categories:
- **Type labels:** Red/orange/blue tones
- **Priority labels:** Red (critical) → Yellow (low)
- **Component labels:** Light blues and purples
- **Infrastructure labels:** Dark blues
- **Status labels:** Greens and yellows

---

## 🎨 Label Color Scheme

Current color associations:

- **Critical/Security:** Red tones (#D93F0B)
- **High Priority:** Orange tones (#D93F0B)
- **Medium Priority:** Orange (#FFA500)
- **Low Priority:** Yellow (#FBCA04)
- **Bug:** Red (#d73a4a)
- **Enhancement:** Blue (#a2eeef)
- **Documentation:** Blue (#0075ca)
- **Infrastructure:** Dark blue (#0052CC)
- **Testing:** Green (#0E8A16)
- **UI/Preview:** Purple (#D4C5F9)

---

## 🚀 Next Steps

With labels applied and cleaned up, you can now:

1. **Create GitHub Projects** - Organize issues into boards
2. **Create Milestones** - Track v0.1, v0.2, etc. progress
3. **Filter effectively** - Find the work that matters
4. **Prioritize better** - See what's critical at a glance
5. **Onboard contributors** - Help them find good first issues

**Recommended:** Create a GitHub Project board for v0.1 with columns:
- To Do (`label:"v0.1" is:open no:assignee`)
- In Progress (`label:"v0.1" is:open assignee:*`)
- In Review (`label:"v0.1" is:pr`)
- Done (`label:"v0.1" is:closed`)

---

## 📊 All Active Labels

Complete list of all 37 labels currently in use:

| Label | Usage | Description |
|-------|-------|-------------|
| `bug` | 38 | Something isn't working |
| `cloned-issue` | 34 | Cloned from original MacDown |
| `enhancement` | 30 | New feature or request |
| `v0.1` | 27 | Must have for v0.1 release |
| `medium` | 25 | Should do, moderate impact |
| `testing` | 25 | Testing infrastructure and test cases |
| `high` | 22 | Important for release, significant impact |
| `infrastructure` | 21 | Build system, CI/CD, project infrastructure |
| `rendering` | 14 | Rendering and display issues |
| `build` | 12 | Build system, Xcode configuration |
| `hoedown` | 8 | Related to Hoedown parser |
| `critical` | 7 | Blocking release, critical issues |
| `dependencies` | 7 | Pull requests that update dependencies |
| `low` | 7 | Nice to have, minor impact |
| `ci-cd` | 6 | CI/CD workflows |
| `documentation` | 6 | Improvements or additions to documentation |
| `export` | 6 | PDF/HTML export |
| `editor` | 5 | Text editor pane |
| `preview` | 5 | Preview pane |
| `cloned-pr` | 4 | Based on original MacDown PR |
| `diagrams` | 4 | Mermaid/Graphviz diagrams |
| `file-io` | 4 | File operations, autosave |
| `backlog` | 3 | Not scheduled yet |
| `preferences` | 3 | Settings and preferences |
| `good-first-issue` | 2 | Good for newcomers |
| `localization` | 2 | i18n, translations |
| `security` | 2 | Security issues |
| `ui` | 2 | User interface, windows, menus |
| `ci/cd` | 1 | CI/CD workflows (duplicate) |
| `cli` | 1 | Command-line tool |
| `code-signing` | 1 | Code signing |
| `help-wanted` | 1 | Extra attention needed |
| `javascript` | 1 | JavaScript code |
| `markdown-parsing` | 1 | Markdown parsing |
| `question` | 1 | Further information requested |
| `syntax` | 1 | Syntax highlighting |
| `upstream` | 1 | Issue in a dependency |

---

**Note:** This guide is a living document. Update it when labels are added, modified, or removed.
