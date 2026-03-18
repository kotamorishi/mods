# mods - macOS Markdown Viewer

## Project Overview
macOS native markdown viewer app (view-only, no editing). Renders markdown files using WebKit for rich display including syntax-highlighted code blocks.

## Tech Stack
- **Language**: Swift 6.2+
- **UI Framework**: SwiftUI (macOS 26.0+, Apple Silicon)
- **Rendering**: WKWebView (WebKit) for markdown display
- **Build**: Xcode 26.3 / Swift Package Manager
- **Target**: macOS only (no iOS/Windows/Linux)

## Architecture
- SwiftUI app lifecycle (`@main App`)
- WebKit-based markdown rendering (Markdown -> HTML -> WKWebView)
- QuickLook Preview Extension for Finder preview
- File opening: double-click (.md association), command-line, QuickLook

## Build & Run Commands
```bash
# Build
xcodebuild -project mods.xcodeproj -scheme mods -configuration Debug build

# Run
open build/Debug/mods.app
# or
xcodebuild -project mods.xcodeproj -scheme mods -configuration Debug build && open build/Debug/mods.app

# Clean
xcodebuild -project mods.xcodeproj -scheme mods clean

# Release build
xcodebuild -project mods.xcodeproj -scheme mods -configuration Release build
```

## Key Conventions
- No editing functionality - this is a viewer only
- Prefer SwiftUI over AppKit unless WebKit integration requires it
- Use NSViewRepresentable to bridge WKWebView into SwiftUI
- Keep the app lightweight and fast-launching
- Support dark mode / light mode via CSS media queries in the HTML template
- Handle file associations via Info.plist UTType declarations
- CLI opening via `open` command or custom URL scheme is sufficient

## File Structure Guidelines
- Single Xcode project (not workspace) unless dependencies require it
- Minimal file count - avoid over-abstraction
- Group: App / Views / Model / Extensions / Preview Extension
- HTML/CSS template for rendering embedded as Swift string or resource file

## Git Workflow
- Always commit and push changes after completing work
- Do not ask for confirmation before committing and pushing — just do it
- Use concise, descriptive commit messages

## Do NOT
- Add any editing or save functionality
- Add iOS/iPadOS/visionOS targets
- Use third-party package managers (CocoaPods, Carthage)
- Over-engineer with unnecessary abstractions or design patterns
- Add features not explicitly requested
