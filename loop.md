# mods — Continuous Improvement Loop

Run this loop to autonomously identify issues, implement improvements, and verify results.
Focus area: **Performance** first, then quality and UX.

## Process

### 1. Identify (Problem)

Analyze the current codebase for the highest-impact improvement opportunity.
Check these areas in priority order:

**Performance:**
- App launch time and time-to-render
- HTML template size (all JS/CSS is embedded inline into every loadHTMLString call)
- Resource loading (emoji.json, JS libraries read from disk on every render)
- mermaid.min.js is ~3MB — loaded even when no mermaid blocks exist
- katex.min.js is ~277KB — loaded even when no math exists
- WKWebView creation overhead
- Memory usage with multiple windows

**Quality:**
- GFM rendering correctness vs github.com
- Dark mode consistency
- QuickLook extension parity with main app
- Edge cases: very large files, empty files, binary files

**UX:**
- File opening workflow
- Window title and state
- Zoom persistence
- Keyboard shortcuts

Pick ONE specific, measurable issue. Write it down clearly.

### 2. Improve (Implementation)

- Read the relevant source files before making changes
- Make the minimal change to fix the identified issue
- Build and verify the change compiles:
  ```
  xcodebuild -project mods.xcodeproj -scheme mods -configuration Debug build SYMROOT=$(pwd)/build DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM CODE_SIGN_IDENTITY="Apple Development"
  ```
- Do NOT add new features — only improve existing behavior
- Do NOT refactor code that isn't related to the issue

### 3. Evaluate (Verification)

- Confirm build succeeds
- If performance: measure before/after (file sizes, timing, memory)
- If quality: test with `test/gfm-full-test.md`
- If the change made things worse, revert it
- Commit and push the change with a descriptive message

### 4. Repeat

Go back to step 1 and pick the next issue.
Stop after 3 cycles per session unless instructed otherwise.

## Current Known Issues (starting backlog)

1. **HTML bloat**: Every render embeds ~3.4MB of JS inline into the HTML string (mermaid alone is 3MB). This is loaded even for simple READMEs with no diagrams.
2. **Resource caching**: emoji.json, JS, and CSS files are re-read from disk on every file open.
3. **Lazy loading**: KaTeX and Mermaid should only load when the markdown actually contains math or mermaid blocks.
4. **QuickLook code duplication**: MarkdownRendererQL duplicates MarkdownRenderer logic.
5. **Large file handling**: No guard against extremely large markdown files that could freeze the app.
