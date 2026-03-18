# mods

A lightweight macOS native markdown viewer. View-only — no editing.

## Features

- Renders markdown files with rich formatting via WebKit
- Syntax-highlighted code blocks (highlight.js)
- Dark mode / light mode support
- Multiple windows for viewing several files at once
- Zoom in/out (Cmd+, Cmd-)
- Open .md files via double-click, File > Open, or drag & drop
- QuickLook preview in Finder (Space key)

## Requirements

- macOS 26.0+
- Apple Silicon
- Xcode 26+ (for building)

## Build

Set your Apple Developer Team ID before building:

```bash
export DEVELOPMENT_TEAM="your-team-id"
```

```bash
# Build
xcodebuild -project mods.xcodeproj -scheme mods -configuration Debug build \
  SYMROOT=$(pwd)/build DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM CODE_SIGN_IDENTITY="Apple Development"

# Build and run
xcodebuild -project mods.xcodeproj -scheme mods -configuration Debug build \
  SYMROOT=$(pwd)/build DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM CODE_SIGN_IDENTITY="Apple Development" \
  && open build/Debug/mods.app

# Install (required for QuickLook extension)
cp -R build/Debug/mods.app /Applications/mods.app

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
