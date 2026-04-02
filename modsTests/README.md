# Unit Tests Setup

Test files are ready but the Xcode test target needs to be created manually:

1. Open `mods.xcodeproj` in Xcode
2. File > New > Target > macOS > Unit Testing Bundle
3. Name: `modsTests`, Language: Swift
4. In the test target's Build Settings:
   - Set `SWIFT_VERSION` to 6.0
   - Set `MACOSX_DEPLOYMENT_TARGET` to 26.0
5. In the test target's Build Phases > Link Binary With Libraries:
   - Add `CMarkGFM` from the swift-cmark-gfm package
6. Delete the auto-generated test file and add the existing files:
   - `modsTests/MarkdownRendererTests.swift`
   - `modsTests/HTMLBuilderTests.swift`
7. Run tests: Cmd+U or `xcodebuild test -scheme modsTests`
