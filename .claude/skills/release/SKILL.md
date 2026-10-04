---
name: release
description: Build Harbor Release, tag and publish to GitHub Releases, install to /Applications, and relaunch. Use when the user wants to ship a new version to end users so the auto-updater picks it up.
---

# Release Harbor

Full release flow: tag, GitHub release, build, version verification, notarization, upload, install, relaunch. For local-only installs without publishing, use `/install` instead.

## Steps

1. **Read version from project.yml** — extract `MARKETING_VERSION` value.

2. **Check for uncommitted changes** — run `git status --porcelain`. If there are changes, stop and ask the user to commit first.

3. **Verify git tag** — check if a git tag `v{version}` exists. If not, create the tag and push it.

4. **Verify GitHub release** — check if a GitHub release for `v{version}` exists. If not, create it with `gh release create v{version} --title "Harbor v{version}" --generate-notes`.

5. **Kill running Harbor** — `killall Harbor 2>/dev/null`

6. **Build Release** — run `xcodebuild -project Harbor.xcodeproj -scheme Harbor -configuration Release clean build`. Fail if build fails.

7. **Verify built version and signature** — read `CFBundleShortVersionString` from the built app's Info.plist in DerivedData. It MUST match the MARKETING_VERSION from project.yml. Then `codesign -dvv` the app and confirm `Authority=Developer ID Application` and `TeamIdentifier=735SV765PC`. Stop on any mismatch. The in-app updater rejects updates not signed by this team.

8. **Notarize** — zip the built app (`ditto -ck --keepParent <built>/Harbor.app /tmp/Harbor-notarize.zip`), then `xcrun notarytool submit /tmp/Harbor-notarize.zip --keychain-profile harbor --wait`. If status is not `Accepted`, run `xcrun notarytool log <id> --keychain-profile harbor` and stop. If the `harbor` profile is missing, tell the user to run `xcrun notarytool store-credentials harbor` themselves (it needs an app-specific password — never enter it for them).

9. **Staple and assess** — `xcrun stapler staple <built>/Harbor.app`, then `spctl -a -vvv -t exec <built>/Harbor.app` must report `source=Notarized Developer ID`.

10. **Copy to /Applications** — IMPORTANT: `rm -rf /Applications/Harbor.app` first, THEN `cp -R` the stapled app. A plain `cp -R` over an existing .app bundle does not reliably replace all files.

11. **Create zip and upload** — use `ditto -ck --sequesterRsrc --keepParent /Applications/Harbor.app /tmp/Harbor.app.zip`, then `gh release upload v{version} /tmp/Harbor.app.zip --clobber`. Clean up both temp zips after.

12. **Verify uploaded zip** — download the release zip to a temp dir, extract it, confirm `CFBundleShortVersionString` matches the expected version and `spctl -a -t exec` accepts it. If not, stop and report the error.

13. **Launch Harbor** — `open /Applications/Harbor.app`

14. Report success with the version number.
