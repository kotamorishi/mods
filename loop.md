# mods — Continuous Improvement Loop

Run this loop to autonomously identify issues, implement improvements, and verify results.
Focus area: **Performance** first, then quality and UX.

## Process

### 1. Identify (Problem)

Analyze the current codebase for the highest-impact improvement opportunity.
Check these areas in priority order:

**Performance:**
- App launch time and time-to-render
- Memory usage with multiple windows
- WKWebView creation overhead

**Quality:**
- GFM rendering correctness vs github.com
- Dark mode consistency
- Edge cases: unusual markdown syntax, non-UTF8 files

**UX:**
- Zoom persistence across sessions
- Keyboard shortcuts
- Window management

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

## Completed Improvements

| Cycle | Type | Description |
|-------|------|-------------|
| 1 | Perf | Lazy-load Mermaid (~3MB) and KaTeX (~280KB) — only when content needs them |
| 2 | Perf | Apply same lazy-loading to QuickLook extension |
| 3 | Quality | Share MarkdownRenderer between app and QL via symlink (-117 lines) |
| 4 | Quality | Add 10MB file size guard to prevent memory issues |
| 5 | Perf | Cache static CSS style block — built once, reused across renders |
| 6 | Perf | Cache base head, footer script, mermaid/katex blocks as statics |
| 7 | Perf | Fix over-eager KaTeX detection (regex instead of `contains("$")`) |
| 8 | Perf | Replace character-by-character emoji processing with regex |
| 9 | UX | Handle file opening from Finder and `open` command via onOpenURL |
| 10 | Quality | Fix empty file showing placeholder instead of blank page |
| 11 | Perf | Apply static caching to QuickLook extension HTML template |
| 12 | Quality | Align QuickLook font size/padding with main app |
| 13 | Quality | Extract shared CSS into mods.css resource file (single source of truth) |

## Remaining Opportunities

- **File watching**: Auto-reload when the .md file changes on disk (feature — needs user request)
- **Scroll position**: Preserve scroll position when reloading a file
- **Window restoration**: Remember open files across app restarts
- **Print support**: Cmd+P to print rendered markdown
- **Search in document**: Cmd+F to find text in rendered view
