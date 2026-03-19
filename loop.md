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
| 14 | Quality | Update loop.md backlog to reflect completed work |
| 15 | Quality | Handle non-UTF8 file encoding with fallback (Latin-1, Shift-JIS, UTF-16) |
| 16 | Quality | Remove dead do/catch in QL extension; untrack icon.jpg |
| 17 | Quality | Fix alert processing for multi-paragraph and complex content |
| 18 | Quality | Fix WKNavigationDelegate warning with modern async API (zero warnings) |
| 19 | Perf | Replace duplicated QL resources with symlinks (-3.4MB from git repo) |
| 20 | Perf | Inject highlight.js via WKUserScript — parsed once, not per render |
| 21 | Perf | Use evaluateJavaScript for content swap without page reload |
| 22 | Perf | Apply WKUserScript optimization to QuickLook extension |
| 23 | Perf | Add early-exit checks to skip unnecessary post-processing |
| 24 | Perf | Use regex pre-check for emoji to avoid loading map for URL colons |
| 25 | Perf | Read file data once for encoding fallback instead of per attempt |
| 26 | UX | Reset scroll to top when switching files via evaluateJavaScript |
| 27 | Quality | Extract shared HTMLBuilder to eliminate QL code duplication (-22%) |
| 28 | Quality | Fix MainActor isolation warning, verify zero-warning Release build |
| 29 | Perf | Load QL resources from parent app bundle (app 9.2→5.9MB, -36%) |
| 30 | Perf | Cache compiled alert regexes as static let |
| 31 | Perf | Cache compiled color chip regexes and deduplicate template |
| 32 | Quality | Update loop.md, mark performance optimization exhausted |
| 33 | Security | Fix mermaid/katex broken by allowsContentJavaScript=false |
| 34 | Security | Fix same mermaid/katex bug in QuickLook extension |
| 35 | UX | Implement working Cmd+F find bar with highlighting |
| 36 | Quality | Remove unused variable warning, verify zero-warning Release |
| 37 | Perf | Cache alt text regex and add early exit in blockExternalImages |
| 38 | Perf | Move emoji exclusion regexes to static let (all 13 regexes now static) |
| 39 | Security | Fix CSP to allow click-to-load images while blocking other resources |

## Features Added

| Feature | Description |
|---------|-------------|
| File watching | Auto-reload when .md file changes on disk (DispatchSource) |
| Security: Content JS | `allowsContentJavaScript=false` — page JS disabled, WKUserScript bypasses |
| Security: Sanitization | Strip script/iframe/object/embed/form, event handlers, javascript: URLs |
| Security: CSP | `default-src 'none'` with explicit allowlists per resource type |
| Security: Navigation | Block all navigation except initial load; links open in browser |
| Security: Images | External images blocked by default, click-to-load with placeholder |
| Security: Referrer | `no-referrer` policy prevents context leaking |
| Search | Cmd+F find bar with live highlighting, match count, next/close |
| Encoding fallback | UTF-8, Latin-1, Shift-JIS, UTF-16, ASCII with single disk read |

## Remaining Opportunities

**Features (require user request):**
- Multiple windows: open each file in a new window
- Print support: Cmd+P to print rendered markdown
- Window restoration: remember open files across app restarts

**Quality:**
- Test coverage: no automated tests exist

**Status: Performance and security optimization exhausted.** All caching, lazy-loading, regex compilation, resource sharing, rendering optimizations, and security hardening applied.
