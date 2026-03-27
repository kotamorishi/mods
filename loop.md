# mods — Continuous Improvement Loop

Run this loop to autonomously identify issues, implement improvements, and verify results.
**Current focus: Security and Stability only. No new features.**

## Process

### 1. Identify

Analyze the current codebase for security vulnerabilities and stability issues.
Pick ONE specific, actionable item from these areas:

**Security:**
- HTML sanitization gaps (new bypass vectors, edge cases)
- CSP policy completeness
- WKWebView attack surface (navigation, JS injection, resource loading)
- File access beyond sandbox boundaries
- Input validation (malformed URLs, paths, file contents)
- Dependency audit (cmark-gfm, highlight.js, KaTeX, Mermaid versions)
- Entitlements minimization

**Stability:**
- Crash scenarios (nil handling, force unwraps, edge cases)
- Memory leaks (WKWebView, FileWatcher, cached resources)
- Thread safety (nonisolated(unsafe) static vars, concurrent access)
- Error handling (graceful degradation, user feedback)
- Edge cases (empty files, binary files, huge headings, deeply nested lists)
- WebView process termination recovery

**Quality (non-feature):**
- Build warnings (Release mode)
- Code correctness (regex edge cases, string handling)
- Test coverage for existing functionality

### 2. Implement

- Read the relevant source files before making changes
- Make the minimal change needed
- Do NOT add new features — only fix security issues, stability bugs, and quality problems
- Build and verify:
  ```
  xcodebuild -project mods.xcodeproj -scheme mods -configuration Debug build SYMROOT=$(pwd)/build DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM CODE_SIGN_IDENTITY="Apple Development"
  ```

### 3. Evaluate

- Confirm build succeeds with zero warnings (Release mode)
- If security: verify the attack vector is blocked
- If stability: verify the edge case is handled gracefully
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
| 60 | Feature | Floating back-to-top button for long documents |
| 61 | Feature | Custom CSS support via ~/.config/mods/custom.css |
| 62 | Bug | Fix custom CSS path for sandboxed App Store builds |
| 63 | Quality | Final Release build verification and loop.md update |
| 64 | Quality | Clean up obsolete files, verify archive build |
| 65 | UX | Show file directory path in status bar |
| 66 | UX | Remove irrelevant context menu items from WebView |
| 67 | UX | Add Cmd+Shift+T keyboard shortcut for TOC |
| 68 | UX | Add Cmd+0 to reset zoom to 100% |
| 69 | Quality | Extract duplicated NSOpenPanel into FilePickerHelper |
| 70 | Quality | Fix FilePickerHelper MainActor warning, final Release check |
| 71 | Security | Expand sanitization: block SVG, meta, base, link, CSS expressions |
| 72 | Security | Thread-safe cmark-gfm extension registration (dispatch_once) |
| 73 | Security | Fix sanitization bypass with unquoted attribute values |
| 74 | Security | Fix JS injection via crafted markdown headings in TOC |
| 75 | Security | Replace 7/8 nonisolated(unsafe) with thread-safe patterns |
| 76 | Security | Audit dependency versions — all current, no known CVEs |

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

1. **Homebrew formula** — `brew install --cask mods`
2. **Test coverage** — unit tests for MarkdownRenderer, HTMLBuilder

## Dependency Versions (audited cycle 76)

| Library | Version | License | CVEs |
|---------|---------|---------|------|
| highlight.js | 11.11.1 | BSD-3-Clause | None |
| KaTeX | 0.16.22 | MIT | None |
| Mermaid | 11.x | MIT | None |
| cmark-gfm | 0.29.0.gfm.13 | BSD-2-Clause | None |
| gemoji | 1913 entries | MIT | N/A |

## Stats

- **App size**: 6.2 MB (Release)
- **Source**: ~1350 lines Swift, 6 files + 1 QL extension
- **Build warnings**: 0
- **Improvement cycles**: 76
- **Features**: 26
- **Security layers**: 9 (sanitization, CSP, content JS, navigation, images, referrer, thread safety, context menu, input validation)
