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
| 47 | Quality | Verify Release build, update loop.md |
| 48 | Feature | Copy button on code blocks (hover to reveal) |
| 49 | Feature | `mods://` URL scheme for scriptable file opening |
| 50 | Quality | Fix copy button with legacy clipboard fallback |
| 51 | Quality | Add accessibility attributes to JS-injected UI |
| 52 | Quality | Update README and App Store description with all features |
| 53 | Bug | Fix find bar buttons broken by allowsContentJavaScript=false |
| 54 | Quality | Fix find bar dark mode styling |
| 55 | UX | Close welcome window when opening a file from it |
| 56 | Bug | Fix File > Open when no windows are open |
| 57 | Quality | Audit Release bundle, commit project file |
| 58 | Bug | Handle onOpenURL in FileView for when welcome window is closed |

## Features

| Feature | Description |
|---------|-------------|
| GFM rendering | cmark-gfm (same engine as GitHub), tables, footnotes, alerts |
| Syntax highlighting | 16+ languages via highlight.js |
| Math (KaTeX) | Inline `$...$` and block `$$...$$` expressions |
| Mermaid diagrams | Flowcharts, sequence diagrams via mermaid.js |
| Emoji shortcodes | 1913 GitHub emoji via gemoji data |
| Color chips | Visual swatches for hex/rgb/hsl in inline code |
| Multiple windows | Each file opens in its own window |
| Find (Cmd+F) | Find bar with live highlighting, match count, next/close |
| Print (Cmd+P) | Print via system print dialog |
| Export PDF (Cmd+Shift+E) | Save rendered markdown as PDF |
| Table of Contents | Toolbar popover with heading outline navigation |
| Word count | Status bar with word count and reading time |
| Copy code blocks | Hover-to-reveal copy button on code blocks |
| File watching | Auto-reload when .md file changes on disk |
| Open Recent | File > Open Recent menu |
| URL scheme | `mods:///path/to/file.md` for scripting |
| QuickLook | Preview .md files in Finder (Space key) |
| Encoding fallback | UTF-8 → Latin-1 → Shift-JIS → UTF-16 → ASCII |
| External image blocking | Click-to-load placeholders for security |
| Content Security Policy | `default-src 'none'` with per-type allowlists |
| HTML sanitization | Strip script/iframe/object/embed/form tags |
| Navigation blocking | Links open in default browser, not in WebView |
| Accessibility | ARIA labels on all JS-injected UI elements |

## Backlog

1. **Custom CSS** — allow user to override styles via preferences
2. **Homebrew formula** — `brew install --cask mods` for easy installation
3. **Test coverage** — unit tests for MarkdownRenderer, HTMLBuilder
4. **Syntax theme selection** — light/dark highlight.js themes
5. **Back to top** — floating button for long documents

## Stats

- **App size**: 6.2 MB (Release)
- **Source**: 1199 lines Swift, 6 files + 1 QL extension
- **Build warnings**: 0
- **Improvement cycles**: 59
- **Features**: 23
