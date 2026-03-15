---
name: build
description: Build Harbor Debug and run it locally
---

# Build Harbor

Build a Debug version of Harbor and run it from the build directory.

## Steps

1. Kill any running Harbor instance
2. Build Debug configuration: `xcodebuild -project Harbor.xcodeproj -scheme Harbor -configuration Debug build -quiet`
3. Launch from build directory: `open <BUILT_PRODUCTS_DIR>/Debug/Harbor.app`
4. Report success or failure
