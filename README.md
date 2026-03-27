# mods

A fast, lightweight macOS native markdown viewer. View-only — no editing.

[![mods app icon](icon.png)](https://apps.apple.com/app/mods-markdown-viewer/id6760838590)

[Download on the Mac App Store](https://apps.apple.com/app/mods-markdown-viewer/id6760838590)

Renders GitHub Flavored Markdown with the same engine GitHub uses ([cmark-gfm](https://github.com/github/cmark-gfm)).

## Features

**Rendering**
- Full GitHub Flavored Markdown (GFM) compliance
- Syntax-highlighted code blocks (16+ languages)
- Tables, task lists, footnotes, strikethrough
- Math expressions (KaTeX)
- Mermaid diagrams
- Emoji shortcodes (:rocket: etc.)
- GitHub-style alerts ([!NOTE], [!WARNING], etc.)
- Color chips for hex/rgb/hsl in inline code
- Dark mode / light mode support

**Viewer**
- Multiple windows — each file in its own window
- Zoom in/out (Cmd+/Cmd-)
- Find in document (Cmd+F) with live highlighting
- Table of Contents popover for heading navigation
- Word count and reading time status bar
- Copy button on code blocks
- Auto-reload when file changes on disk

**Export & Print**
- Print (Cmd+P)
- Export as PDF (Cmd+Shift+E)

**File Opening**
- Double-click .md files in Finder
- File > Open (Cmd+O) with multiple selection
- File > Open Recent
- Drag & drop
- QuickLook preview in Finder (Space key)
- `mods://` URL scheme for scripting
- `open -a mods file.md` from terminal

**Security**
- External images blocked by default (click to load)
- Content JavaScript disabled (prevents XSS from markdown)
- HTML sanitization (strips script/iframe/object tags)
- Content Security Policy headers
- No tracking, no analytics, no network requests

## Requirements

- macOS 26.0+
- Apple Silicon
- Xcode 26+ (for building)

## Build

```bash
export DEVELOPMENT_TEAM="your-team-id"

# Build and run
xcodebuild -project mods.xcodeproj -scheme mods -configuration Debug build \
  SYMROOT=$(pwd)/build DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM CODE_SIGN_IDENTITY="Apple Development" \
  && open build/Debug/mods.app

# Install (required for QuickLook extension registration)
cp -R build/Debug/mods.app /Applications/mods.app

# Clean
xcodebuild -project mods.xcodeproj -scheme mods clean
```

## Custom CSS

Override default styles by creating a custom CSS file:

```bash
# App Store / sandboxed builds:
mkdir -p ~/Library/Application\ Support/mods
# Development builds (fallback):
mkdir -p ~/.config/mods
```

```css
/* ~/Library/Application Support/mods/custom.css */

/* Example: wider content, larger font */
body { max-width: 1200px; font-size: 18px; }

/* Example: custom code block background */
pre { background-color: #1e1e2e; }
```

Changes take effect on next file open (restart for cached windows).

## Tech Stack

- Swift / SwiftUI (macOS 26.0+)
- [cmark-gfm](https://github.com/github/cmark-gfm) (BSD-2-Clause) — GitHub's markdown parser
- WKWebView (WebKit) for rendering
- [highlight.js](https://github.com/highlightjs/highlight.js) (BSD-3-Clause) — Syntax highlighting
- [KaTeX](https://github.com/KaTeX/KaTeX) (MIT) — Math rendering
- [Mermaid](https://github.com/mermaid-js/mermaid) (MIT) — Diagrams
- [gemoji](https://github.com/github/gemoji) (MIT) — Emoji data

## Privacy

mods does not collect, store, or transmit any data. See [PRIVACY.md](PRIVACY.md).

## License

GPLv3 — see [LICENSE](LICENSE).
