# Markdown Renderer Replacement Plan

## Problem

Current implementation uses marked.js (JavaScript) in WKWebView to convert Markdown to HTML. This causes:

1. **Rendering artifacts** — bullet points display as `・    •    Render` with extra dots and spacing
2. **WKWebView sandbox issues** — black screen in certain sandbox configurations
3. **No direct control** — JavaScript library is a black box; CSS conflicts with WKWebView defaults cause unpredictable output

## Goal

Replace marked.js with a Swift-native Markdown-to-HTML pipeline that:
- Fully conforms to GitHub Flavored Markdown (GFM) spec
- Gives complete control over HTML output
- Eliminates JavaScript dependency for Markdown parsing
- Still uses WKWebView for final HTML display (CSS/layout control)

## Approach: cmark-gfm via Swift Package

### Why cmark-gfm

**cmark-gfm** is the C library that GitHub itself uses to render Markdown. It is the reference implementation of GFM.

- **License**: BSD 2-Clause (GPLv3 compatible)
- **GFM features**: tables, strikethrough, autolinks, task lists, footnotes — all supported
- **HTML output**: built-in `cmark_render_html()` produces GitHub-identical HTML
- **Battle-tested**: used in production by GitHub.com

### Swift wrapper: swift-cmark-gfm

Use `stackotter/swift-cmark-gfm` (Apache 2.0) as Swift Package Manager dependency. This wraps cmark-gfm's C library for direct Swift access.

Alternative: use `github/cmark-gfm` directly as a C package via SPM.

### Rejected alternatives

| Library | Reason |
|---------|--------|
| apple/swift-markdown | No HTML output — AST only, would need custom renderer |
| JohnSundell/Ink | Missing task lists, not full GFM compliant |
| loopwerk/Parsley | Higher-level wrapper but less control, may not expose all extensions |
| marked.js (current) | JavaScript; rendering artifacts in WKWebView |

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌───────────┐
│  .md file   │ ──> │  cmark-gfm   │ ──> │  HTML string │ ──> │ WKWebView │
│  (String)   │     │  (C library) │     │  + CSS       │     │ (display) │
└─────────────┘     └──────────────┘     └──────────────┘     └───────────┘
```

### Components

1. **MarkdownRenderer.swift** — Swift wrapper that calls cmark-gfm C API
   - Enable extensions: tables, strikethrough, autolinks, tagfilter, tasklist, footnotes
   - Parse markdown string → cmark AST
   - Render AST → HTML string
   - Post-process: GitHub alert blocks (`[!NOTE]`, `[!WARNING]`, etc.)

2. **MarkdownWebView.swift** — NSViewRepresentable (unchanged role)
   - Receives pre-rendered HTML (no more JavaScript parsing)
   - Loads HTML template with GitHub CSS + highlight.js (syntax highlighting only)
   - WKWebView only runs highlight.js for code coloring, not markdown parsing

3. **GitHub CSS** — keep existing github.min.css / github-dark.min.css

4. **highlight.js** — keep for syntax highlighting in code blocks only

### QuickLook Extension

Same approach: cmark-gfm renders HTML, NSTextView displays via NSAttributedString(html:). No WKWebView needed.

## GFM Test Cases

Each feature must be visually verified against github.com rendering:

| # | Feature | Test |
|---|---------|------|
| 1 | Headings (h1-h6) | `# H1` through `###### H6` |
| 2 | Bold | `**bold**` |
| 3 | Italic | `*italic*` |
| 4 | Strikethrough | `~~text~~` |
| 5 | Inline code | `` `code` `` |
| 6 | Code blocks | ` ```lang ... ``` ` |
| 7 | Code blocks (no lang) | ` ``` ... ``` ` |
| 8 | Blockquotes | `> quote` |
| 9 | Nested blockquotes | `> > nested` |
| 10 | Unordered list | `- item` |
| 11 | Ordered list | `1. item` |
| 12 | Nested lists | Indented sub-items |
| 13 | Task lists | `- [x] done` / `- [ ] todo` |
| 14 | Tables | `| a | b |` with header separator |
| 15 | Links | `[text](url)` |
| 16 | Images | `![alt](url)` |
| 17 | Horizontal rule | `---` |
| 18 | Footnotes | `text[^1]` / `[^1]: note` |
| 19 | Autolinks | `https://example.com` |
| 20 | HTML inline | `<sub>`, `<sup>`, `<ins>`, `<kbd>` |
| 21 | Alerts | `> [!NOTE]`, `> [!WARNING]`, etc. |
| 22 | Escaped chars | `\*not italic\*` |
| 23 | Line breaks | Two spaces + newline |
| 24 | Paragraphs | Blank line between |

## Implementation Steps

1. Add `swift-cmark-gfm` SPM dependency to Xcode project
2. Create `MarkdownRenderer.swift` — cmark-gfm wrapper with all GFM extensions
3. Update `MarkdownWebView.swift` — use pre-rendered HTML, remove marked.js from HTML template
4. Update QuickLook extension — use same MarkdownRenderer
5. Remove marked.js from bundle (keep highlight.js for syntax highlighting)
6. Test all 24 cases against `test/gfm-test.md`
7. Compare rendering with github.com side-by-side

## Risks

- **SPM dependency**: Project currently uses no SPM packages. Adding one requires converting to .xcworkspace or adding Package.swift resolution to .xcodeproj.
- **cmark-gfm alerts**: GFM alerts (`[!NOTE]` etc.) are NOT part of cmark-gfm's extensions — need post-processing of HTML output.
- **Syntax highlighting**: Still needs highlight.js in WKWebView for code block coloring. This is acceptable since it's display-only, not parsing.
