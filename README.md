# mods

A lightweight macOS native markdown viewer. View-only — no editing.

## Features

- Renders markdown files with rich formatting via WebKit
- Syntax-highlighted code blocks (highlight.js)
- Dark mode / light mode support
- Multiple windows for viewing several files at once
- Zoom in/out (Cmd+, Cmd-)
- Open .md files via double-click, File > Open, or `open` command

## Requirements

- macOS 26.0+
- Apple Silicon

## Build

```bash
# Build
xcodebuild -project mods.xcodeproj -scheme mods -configuration Debug build

# Build and run
xcodebuild -project mods.xcodeproj -scheme mods -configuration Debug build && open ~/Library/Developer/Xcode/DerivedData/mods-*/Build/Products/Debug/mods.app

# Clean
xcodebuild -project mods.xcodeproj -scheme mods clean
```

## Tech Stack

- Swift / SwiftUI
- WKWebView (WebKit) for rendering
- [marked.js](https://github.com/markedjs/marked) (MIT) — Markdown parser
- [highlight.js](https://github.com/highlightjs/highlight.js) (BSD-3-Clause) — Syntax highlighting

## License

GPLv3 — see [LICENSE](LICENSE).
