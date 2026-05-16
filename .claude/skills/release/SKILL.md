---
name: release
description: Build Harbor Release, tag and publish to GitHub Releases, install to /Applications, and relaunch. Use when the user wants to ship a new version to end users so the auto-updater picks it up.
---

# Release Harbor

Full release flow: tag, GitHub release, build, version verification, upload, install, relaunch. For local-only installs without publishing, use `/install` instead.

## Steps

1. **Read version from project.yml** — extract `MARKETING_VERSION` value.

2. **Check for uncommitted changes** — run `git status --porcelain`. If there are changes, stop and ask the user to commit first.

3. **Verify git tag** — check if a git tag `v{version}` exists. If not, create the tag and push it.

4. **Verify GitHub release** — check if a GitHub release for `v{version}` exists. If not, create it with `gh release create v{version} --title "Harbor v{version}" --generate-notes`.

5. **Kill running Harbor** — `killall Harbor 2>/dev/null`

6. **Build Release** — run `xcodebuild -project Harbor.xcodeproj -scheme Harbor -configuration Release clean build`. Fail if build fails.

7. **Verify built version matches** — read `CFBundleShortVersionString` from the built app's Info.plist in DerivedData. It MUST match the MARKETING_VERSION from project.yml. If it doesn't, stop and report the mismatch.

8. **Copy to /Applications** — IMPORTANT: `rm -rf /Applications/Harbor.app` first, THEN `cp -R` the built app. A plain `cp -R` over an existing .app bundle does not reliably replace all files.

9. **Restore Info.plist** — run `git checkout -- Harbor/Info.plist` (the pre-build script modifies it with the git hash).

10. **Create zip and upload** — use `ditto -ck --sequesterRsrc --keepParent /Applications/Harbor.app /tmp/Harbor.app.zip`, then `gh release upload v{version} /tmp/Harbor.app.zip --clobber`. Clean up the temp zip after.

11. **Verify uploaded zip** — download the release zip to a temp dir, extract it, and confirm `CFBundleShortVersionString` matches the expected version. If it doesn't, stop and report the error.

12. **Launch Harbor** — `open /Applications/Harbor.app`

13. Report success with the version number.
