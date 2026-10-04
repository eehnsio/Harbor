---
name: install
description: Build Harbor Release locally and install to /Applications without publishing. Use when the user wants to try the latest build on their own machine but not push it to users.
---

# Install Harbor locally

Build a Release version of Harbor and install it to `/Applications` without touching git tags or GitHub releases. For the public release flow, use `/release` instead.

## Steps

1. Kill any running Harbor instance and wait 1 second for it to exit
2. Build Release configuration: `xcodebuild -project Harbor.xcodeproj -scheme Harbor -configuration Release clean build -quiet`
   - Release is signed with the "Developer ID Application" certificate (team 735SV765PC). If the build fails with a missing identity, tell the user to create it in Xcode → Settings → Accounts → Manage Certificates.
3. **Remove** old app first, then copy: `rm -rf /Applications/Harbor.app && cp -R <BUILT_PRODUCTS_DIR>/Release/Harbor.app /Applications/Harbor.app`
4. Launch: `open /Applications/Harbor.app`
5. Report the app size and confirm success

No notarization here — the app is built locally, so it has no quarantine flag and Gatekeeper won't check it.
