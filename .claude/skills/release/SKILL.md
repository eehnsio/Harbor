---
name: release
description: Build Harbor Release, copy to /Applications, and relaunch
disable-model-invocation: true
---

# Release Harbor

Build a Release version of Harbor, install it to /Applications, and launch it.

## Steps

1. Kill any running Harbor instance
2. Build Release configuration: `xcodebuild -project Harbor.xcodeproj -scheme Harbor -configuration Release build -quiet`
3. Copy the built app: `cp -R <BUILT_PRODUCTS_DIR>/Release/Harbor.app /Applications/Harbor.app`
4. Launch: `open /Applications/Harbor.app`
5. Report the app size and confirm success
