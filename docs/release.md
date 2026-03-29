# Release Guide

How to build, sign, notarize, and distribute mods via Homebrew cask and GitHub Releases.

## Prerequisites

- Xcode 26+ with command-line tools
- Developer ID Application certificate (`Developer ID Application: kohta morishita (7M75V64ZE5)`)
- Apple ID with app-specific password for notarization
- `gh` CLI authenticated with GitHub

## 1. Update Version

In Xcode, update **both targets** (mods + mods QuickLook Extension):

- **CFBundleShortVersionString** (e.g. `1.4`)
- **CFBundleVersion** (e.g. `1`)

Or via command line:

```bash
# Check current version
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" mods/Info.plist
/usr/libexec/PlistBuddy -c "Print CFBundleVersion" mods/Info.plist
```

## 2. Release Build

```bash
# Clean
xcodebuild -project mods.xcodeproj -target mods clean

# Build Release with Developer ID signing
xcodebuild -project mods.xcodeproj -target mods -configuration Release build \
  SYMROOT=$(pwd)/build \
  DEVELOPMENT_TEAM=7M75V64ZE5 \
  CODE_SIGN_IDENTITY="Developer ID Application"
```

Verify the build:

```bash
# Check version
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/Release/Mods.app/Contents/Info.plist

# Check signing
codesign -dvv build/Release/Mods.app
codesign -dvv "build/Release/Mods.app/Contents/PlugIns/mods QuickLook Extension.appex"

# Verify entitlements include App Groups
codesign -d --entitlements - build/Release/Mods.app
codesign -d --entitlements - "build/Release/Mods.app/Contents/PlugIns/mods QuickLook Extension.appex"
```

## 3. Notarize

```bash
# Create zip for notarization
ditto -c -k --keepParent build/Release/Mods.app Mods-notarize.zip

# Submit for notarization
xcrun notarytool submit Mods-notarize.zip \
  --apple-id "YOUR_APPLE_ID" \
  --team-id 7M75V64ZE5 \
  --password "YOUR_APP_SPECIFIC_PASSWORD" \
  --wait

# Staple the notarization ticket
xcrun stapler staple build/Release/Mods.app

# Verify notarization
spctl -a -vvv build/Release/Mods.app
```

Replace `YOUR_APPLE_ID` and `YOUR_APP_SPECIFIC_PASSWORD` with your Apple ID and app-specific password.

You can store credentials in keychain to avoid passing them each time:

```bash
xcrun notarytool store-credentials "mods-notarize" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id 7M75V64ZE5 \
  --password "YOUR_APP_SPECIFIC_PASSWORD"

# Then use:
xcrun notarytool submit Mods-notarize.zip --keychain-profile "mods-notarize" --wait
```

## 4. Create Distribution Zip

```bash
VERSION=$(defaults read "$(pwd)/build/Release/Mods.app/Contents/Info" CFBundleShortVersionString)

# Create final zip (after stapling)
cd build/Release
ditto -c -k --keepParent Mods.app "../../Mods-${VERSION}.zip"
cd ../..

# Verify
echo "Created Mods-${VERSION}.zip"
ls -lh "Mods-${VERSION}.zip"
```

## 5. GitHub Release

```bash
VERSION=$(defaults read "$(pwd)/build/Release/Mods.app/Contents/Info" CFBundleShortVersionString)

# Create release with zip
gh release create "v${VERSION}" "Mods-${VERSION}.zip" \
  --title "Mods v${VERSION}" \
  --notes "## What's New in v${VERSION}

- Feature description here
"
```

## 6. Update Homebrew Cask

```bash
VERSION=$(defaults read "$(pwd)/build/Release/Mods.app/Contents/Info" CFBundleShortVersionString)
SHA256=$(shasum -a 256 "Mods-${VERSION}.zip" | awk '{print $1}')

echo "Version: ${VERSION}"
echo "SHA256:  ${SHA256}"
```

Update the cask formula in `kotamorishi/homebrew-mods`:

```bash
# Clone tap repo (if not already)
cd /opt/homebrew/Library/Taps/kotamorishi/homebrew-mods

# Edit Casks/mods.rb
# Update version and sha256 with values above
```

The cask file (`Casks/mods.rb`) should look like:

```ruby
cask "mods" do
  version "NEW_VERSION"
  sha256 "NEW_SHA256"

  url "https://github.com/kotamorishi/mods/releases/download/v#{version}/Mods-#{version}.zip"
  name "Mods"
  desc "macOS native Markdown viewer"
  homepage "https://github.com/kotamorishi/mods"

  depends_on macos: ">= :sequoia"

  app "Mods.app"
end
```

Commit and push:

```bash
cd /opt/homebrew/Library/Taps/kotamorishi/homebrew-mods
git add Casks/mods.rb
git commit -m "Update mods to ${VERSION}"
git push
```

## 7. Verify Installation

```bash
brew update
brew upgrade --cask mods

# Or fresh install
brew install --cask kotamorishi/mods/mods
```

## Quick Reference (All Steps)

```bash
# Full release flow
VERSION=1.4  # Set your target version

# Build
xcodebuild -project mods.xcodeproj -target mods clean
xcodebuild -project mods.xcodeproj -target mods -configuration Release build \
  SYMROOT=$(pwd)/build DEVELOPMENT_TEAM=7M75V64ZE5 CODE_SIGN_IDENTITY="Developer ID Application"

# Notarize
ditto -c -k --keepParent build/Release/Mods.app Mods-notarize.zip
xcrun notarytool submit Mods-notarize.zip --keychain-profile "mods-notarize" --wait
xcrun stapler staple build/Release/Mods.app

# Package
cd build/Release && ditto -c -k --keepParent Mods.app "../../Mods-${VERSION}.zip" && cd ../..

# Release
gh release create "v${VERSION}" "Mods-${VERSION}.zip" --title "Mods v${VERSION}" --notes "Release notes here"

# SHA for Homebrew
shasum -a 256 "Mods-${VERSION}.zip"
```
