# mods — Continuous Improvement Loop

Run this loop to autonomously identify issues, implement improvements, and verify results.

## Process

### 1. Identify

Analyze the current codebase and user experience for the highest-impact opportunity.
Check these areas — pick ONE specific, actionable item:

**Performance:**
- App launch time, render speed, memory usage
- Bundle size optimization
- Any remaining uncached or redundant work

**Quality:**
- GFM rendering correctness vs github.com
- Dark mode consistency
- Edge cases: unusual markdown syntax, large files, binary files
- Build warnings, code duplication

**Security:**
- Review HTML sanitization coverage
- Check for new attack vectors
- Audit entitlements and CSP

**UX / Feature:**
- Multiple windows: open each file in a new window instead of replacing
- Window restoration: remember open files across app restarts
- Drag & drop improvements
- Better error messages and user feedback
- Accessibility (VoiceOver, keyboard navigation)
- Toolbar customization
- Recent files menu
- Touch Bar support (if applicable)
- Localization

**Architecture:**
- Reduce code duplication between app and QL extension
- Test coverage (unit tests for MarkdownRenderer, HTMLBuilder)
- Modularize into Swift Package for reuse

### 2. Implement

- Read the relevant source files before making changes
- Make the minimal change needed
- Build and verify:
  ```
  xcodebuild -project mods.xcodeproj -scheme mods -configuration Debug build SYMROOT=$(pwd)/build DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM CODE_SIGN_IDENTITY="Apple Development"
  ```

### 3. Evaluate

- Confirm build succeeds with zero warnings
- If performance: measure before/after
- If quality: test with `test/gfm-full-test.md`
- If feature: verify it works as expected
- If the change made things worse, revert it
- Commit and push

### 4. Repeat

Go back to step 1. Stop after 3 cycles per session unless instructed otherwise.

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
| 40 | Quality | Update loop.md with cycles 32-39 and final status |
| 41 | Feature | Add Cmd+P print support via WKWebView print operation |
| 42 | Feature | Multiple windows: each file opens in its own window |
| 43 | Feature | File > Open Recent via NSDocumentController |
| 44 | Feature | Export as PDF (Cmd+Shift+E) via WKWebView createPDF |
| 45 | Feature | Word count and reading time status bar |
| 46 | Feature | Table of Contents popover for heading navigation |

## Features

| Feature | Description |
|---------|-------------|
| File watching | Auto-reload when .md file changes on disk (DispatchSource) |
| External image blocking | Block auto-loading, click-to-load placeholder |
| Search (Cmd+F) | Find bar with live highlighting, match count, next/close |
| Print (Cmd+P) | Print rendered markdown via system print dialog |
| Export PDF (Cmd+Shift+E) | Save rendered markdown as PDF |
| Multiple windows | Each file opens in its own window |
| Open Recent | File > Open Recent menu |
| Word count | Status bar with word count and reading time |
| Table of Contents | Toolbar popover with heading outline navigation |
| Encoding fallback | UTF-8 → Latin-1 → Shift-JIS → UTF-16 → ASCII |
| Security: Content JS | Page JS disabled, WKUserScript bypasses |
| Security: Sanitization | Strip dangerous tags, event handlers, javascript: URLs |
| Security: CSP | `default-src 'none'` with per-type allowlists |
| Security: Navigation | Block all except initial load; links open in browser |
| Security: Referrer | `no-referrer` policy |

## Backlog (prioritized)

1. **Accessibility** — VoiceOver support, keyboard navigation in find bar
2. **Custom CSS** — allow user to override styles via preferences
3. **URL scheme** — `mods://open?file=/path/to/file.md` for scriptability
4. **Homebrew formula** — `brew install --cask mods` for easy installation
5. **Test coverage** — unit tests for MarkdownRenderer, HTMLBuilder
6. **Syntax theme selection** — light/dark highlight.js themes
7. **Copy code block** — button to copy code blocks to clipboard
8. **Back to top** — floating button for long documents
