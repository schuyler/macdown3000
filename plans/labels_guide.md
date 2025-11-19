# MacDown 3000 Label System Guide

**Created:** 2025-11-18
**Purpose:** Standardized issue categorization and tracking

---

## 🏷️ Label Categories

### 1. Type (What kind of issue?)
- `type: bug` - Something isn't working correctly
- `type: enhancement` - New feature or improvement
- `type: documentation` - Documentation needs work
- `type: infrastructure` - Build, CI/CD, tooling, dependencies
- `type: security` - Security vulnerability or concern
- `type: performance` - Performance improvement needed
- `type: refactor` - Code cleanup without behavior change
- `type: question` - Further information is requested

### 2. Priority (How urgent?)
- `priority: critical` 🔴 - Blocking release, security issue, data loss
- `priority: high` 🟠 - Important for release, significant impact
- `priority: medium` 🟡 - Should do, moderate impact
- `priority: low` 🟢 - Nice to have, minor impact

### 3. Component/Area (Which part?)
- `component: rendering` - Markdown/HTML/LaTeX rendering
- `component: editor` - Text editor pane
- `component: preview` - Preview pane
- `component: export` - PDF/HTML export
- `component: ui` - User interface, windows, menus
- `component: preferences` - Settings and preferences
- `component: file-io` - File operations, autosave
- `component: diagrams` - Mermaid diagrams
- `component: syntax` - Syntax highlighting
- `component: themes` - Editor/preview themes
- `component: cli` - Command-line tool

### 4. Platform/Technology
- `platform: macos` - macOS-specific issues
- `platform: apple-silicon` - M1/M2/M3 related
- `tech: dependencies` - CocoaPods, npm, gems
- `tech: ci-cd` - GitHub Actions, workflows
- `tech: testing` - Unit tests, integration tests
- `tech: build` - Build system, Xcode configuration
- `tech: localization` - i18n, translations

### 5. Status/Workflow
- `status: ready` - Ready to be worked on
- `status: in-progress` - Someone is actively working on this
- `status: blocked` - Blocked by another issue or external factor
- `status: needs-discussion` - Needs community/maintainer discussion

### 6. Effort/Size
- `size: small` - < 4 hours, simple change
- `size: medium` - 1-3 days, moderate complexity
- `size: large` - 1+ weeks, significant work

### 7. Special Categories
- `good-first-issue` 🌱 - Good for newcomers
- `help-wanted` 🙋 - Extra attention needed
- `breaking-change` ⚠️ - Will break backward compatibility
- `upstream` - Issue in a dependency, not our code

### 8. Milestone/Release
- `milestone: v0.1` - Must have for v0.1 release
- `milestone: backlog` - Not scheduled yet

### 9. Source
- `source: cloned-issue` - Cloned from original MacDown
- `source: cloned-pr` - Based on original MacDown PR

---

## 🎯 Usage Guidelines

### For Contributors

**Finding Work:**
```
Good first issues:
  - Filter: label:"good-first-issue"
  - Small, well-defined tasks

Help wanted:
  - Filter: label:"help-wanted"
  - Issues needing extra attention

By component:
  - Filter: label:"component: editor"
  - Focus on specific area
```

**Issue Triage:**
1. Apply `type:` label (what)
2. Apply `priority:` label (urgency)
3. Apply `component:` labels (where)
4. Apply `size:` if clear (effort)
5. Apply `milestone:` if release-critical
6. Apply special labels as needed

### For Maintainers

**Planning v0.1 Release:**
```
Critical path:
  - Filter: label:"milestone: v0.1" label:"priority: critical"
  - 5 issues that MUST be done

High priority v0.1:
  - Filter: label:"milestone: v0.1" label:"priority: high"
  - 15 issues important for quality

All v0.1 issues:
  - Filter: label:"milestone: v0.1"
  - 27 total issues
```

**By Technology:**
```
Dependencies to update:
  - Filter: label:"tech: dependencies"
  - 3 critical dependency issues

CI/CD improvements:
  - Filter: label:"tech: ci-cd"
  - 2 infrastructure issues
```

---

## 📈 Current Project State

Use GitHub's issue filters to view current state:
- **Release Blockers:** `label:"priority: critical" is:open`
- **Quick Wins:** `label:"good-first-issue" is:open`
- **Help Wanted:** `label:"help-wanted" is:open`

---

## 🔍 Useful Filters

### For Contributors
- **Easy wins:** `label:"good-first-issue" label:"size: small"`
- **Documentation:** `label:"type: documentation"`
- **Your area:** `label:"component: editor"` (pick your component)

### For Project Management
- **This week:** `label:"milestone: v0.1" label:"priority: critical"`
- **Next sprint:** `label:"milestone: v0.1" label:"priority: high"`
- **Backlog:** `label:"milestone: backlog"`
- **Blocked:** `label:"status: blocked"`

### For Quality Assurance
- **Security issues:** `label:"type: security"`
- **Critical bugs:** `label:"type: bug" label:"priority: critical"`
- **macOS compatibility:** `label:"platform: macos"`

---

## 📝 Label Maintenance

### Adding New Labels
If you need a new label:
1. Check if existing label fits
2. Discuss in issue or PR
3. Follow naming convention: `category: name`
4. Choose appropriate color for category
5. Add to this guide

### Modifying Labels
Labels can be edited at:
https://github.com/schuyler/macdown3000/labels

Keep colors consistent within categories.

---

## 🚀 Next Steps

With labels applied, you can now:

1. **Create GitHub Projects** - Organize issues into boards
2. **Create Milestones** - Track v0.1, v0.2, etc. progress
3. **Filter effectively** - Find the work that matters
4. **Prioritize better** - See what's critical at a glance
5. **Onboard contributors** - Help them find good first issues

**Recommended:** Create a GitHub Project board for v0.1 with columns:
- To Do (ready)
- In Progress (status: in-progress)
- Blocked (status: blocked)
- Done (closed)
