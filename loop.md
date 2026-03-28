# mods — Continuous Improvement Loop

Run this loop to implement the multi-highlight search feature.
**Current focus: Enhanced search with persistent multi-color highlights.**

## Goal

Replace the current single-search Cmd+F with a developer-focused multi-highlight search:
- Each search term gets its own highlight color (up to 5 concurrent highlights)
- Highlights persist — searching a new term adds a new color layer, not replaces
- Each highlight can be individually dismissed (X button per term)
- UI is minimal, polished, developer-oriented (think VS Code / IDE search)

## Design

**Highlight colors** (5 slots, assigned in order, recycled when full):
1. Yellow (`#ffd33d80`) 2. Blue (`#58a6ff80`) 3. Green (`#3fb95080`) 4. Orange (`#f0883e80`) 5. Purple (`#bc8cff80`)

**UI layout** — compact toolbar-style bar:
```
[Search field] [Add ⏎] [match count]  | [term1 ×] [term2 ×] [term3 ×] | [Clear All]
```

**Keyboard shortcuts:**
- `Cmd+F` — focus search field
- `Enter` — add current term as new highlight
- `Escape` — close search bar (highlights remain)

## Process

### 1. Propose

Pick ONE incremental step from the roadmap below. Describe:
- What will change (JS, CSS, Swift, or all)
- Expected behavior after this step
- Any risks or edge cases

### 2. Implement

- Read relevant source files before making changes
- Make the minimal change for this step
- Keep the UI polished at every step — no half-broken intermediate states
- Build and verify:
  ```
  xcodebuild -project mods.xcodeproj -target mods -configuration Debug build SYMROOT=$(pwd)/build DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM CODE_SIGN_IDENTITY="Apple Development"
  ```

### 3. Evaluate

- Confirm build succeeds with zero warnings
- Verify the step works as described
- Check dark mode and light mode
- If the change made things worse, revert it
- Commit and push

### 4. Review (every 5th cycle)

- Re-read all changed files end-to-end
- Check for: dead code, duplicated logic, inconsistent naming, performance issues
- Refactor if needed, then commit separately
- Update this loop.md with progress

### 5. Repeat

Go back to step 1. Continue until the feature is complete.

## Roadmap

| Step | Description |
|------|-------------|
| 1 | Refactor current search JS into a `SearchManager` class with clean API |
| 2 | Implement multi-term highlight model (array of `{term, color, matchCount}`) |
| 3 | Render highlights using `<mark>` with per-term color via CSS class |
| 4 | Add pill-style tag UI showing active terms with × dismiss button |
| 5 | **Review** — refactor, clean up, verify dark/light mode |
| 6 | Wire Enter key to add new highlight instead of replacing |
| 7 | Implement individual term removal (× button clears only that term's marks) |
| 8 | Add match count per term displayed in each pill |
| 9 | Implement color slot recycling when 5 slots are full (replace oldest) |
| 10 | **Review** — refactor, performance check with large documents |
| 11 | Add "Clear All" button to dismiss all highlights at once |
| 12 | Polish keyboard navigation (Tab between pills, Delete to remove focused pill) |
| 13 | Animate highlight add/remove (subtle fade-in/out) |
| 14 | Persist highlights across file reload (restore on auto-reload) |
| 15 | **Review** — final refactor, accessibility audit, dark/light mode polish |

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
| 77 | Security | URLValidator.isSafe() rejects non-file/non-mods URLs instead of accepting |
| 78 | UX | Show error alert on PDF export failure instead of silent fail |
| 79 | Security | Replace nonisolated(unsafe) _sharedConfig with @MainActor |
| 80 | Feature | Refactor search JS into SearchManager class with multi-term API |
| 81 | Feature | Multi-term search with pill UI, Enter-to-add, per-term dismiss |
| 82 | Bug | Fix search remove trigger to use Int counter pattern |
| 83 | Feature | Restore search highlights after file auto-reload |
| 84 | Quality | Move highlight colors to CSS with dark mode support |
| 85 | Review | Remove dead code, fix highlight nesting CSS selector |
| 86 | UX | Clear search field after adding highlight term |
| 87 | Quality | Verify QuickLook Extension build compatibility |
| 88 | UX | Add animations to search pills and highlight bar |
| 89 | UX | Add fade-in animation to WebView highlights |
| 90 | Review | Fix race condition, dead code, validation, dark mode contrast |
| 91 | UX | Add Cmd+Shift+F shortcut to clear all highlights |
| 92 | Quality | Add aria-label to highlight marks for accessibility |

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
| Multi-highlight search | Up to 5 persistent color-coded highlights with pill UI (Cmd+F, Enter to add, Cmd+Shift+F to clear) |
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

1. ~~**Homebrew formula** — `brew install --cask mods`~~ ✅ Done (v1.1)
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
- **Improvement cycles**: 92
- **Features**: 27
- **Security layers**: 9 (sanitization, CSP, content JS, navigation, images, referrer, thread safety, context menu, input validation)
