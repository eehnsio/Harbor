---
name: release
description: Build Harbor Release, copy to /Applications, and relaunch
---

# Release Harbor

Build a Release version of Harbor, install it to /Applications, and launch it.

## Steps

1. Kill any running Harbor instance and wait 1 second for it to exit
2. Build Release configuration: `xcodebuild -project Harbor.xcodeproj -scheme Harbor -configuration Release clean build -quiet`
3. **Remove** old app first, then copy: `rm -rf /Applications/Harbor.app && cp -R <BUILT_PRODUCTS_DIR>/Release/Harbor.app /Applications/Harbor.app`
4. Restore build artifact: `git checkout -- Harbor/Info.plist`
5. Launch: `open /Applications/Harbor.app`
6. Report the app size and confirm success
