# Harbor

[![Latest release](https://img.shields.io/github/v/release/eehnsio/Harbor?color=brightgreen)](https://github.com/eehnsio/Harbor/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black.svg)](https://www.apple.com/macos/)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-yellow.svg)](https://buymeacoffee.com/eehnsio)

Tiny macOS menu bar app that shows your listening dev server ports — grouped by project, with uptime, memory usage, and one-click kill.

![Harbor screenshot](assets/screenshot.png)

## Why Harbor?

When juggling multiple dev servers (Next.js, Vite, Astro, Django, etc.), it's easy to lose track of what's running on which port. Harbor sits in your menu bar and gives you a quick overview — no terminal digging required.

## Features

- Detects listening TCP ports via native `libproc` APIs (no `lsof` subprocess)
- Groups ports by project folder (resolved from process working directory)
- Resolves friendly names from command-line args (e.g. `node` -> "next dev", "astro dev")
- Shows uptime and memory usage per process
- Per-process submenu: Copy URL, Open in Browser, Terminate, Force Kill
- Click a port to open `http://localhost:<port>` in your browser
- Smart filtering: hides debug ports and ephemeral ports by default
- "Show All Ports" toggle to reveal everything
- Launch at Login toggle
- Auto-update via GitHub Releases
- About window with version, GitHub, and support links
- Custom menu bar icon, no Dock icon
- Auto-refreshes every 5 seconds
- ~500 KB, zero dependencies

## Install

### Download

Grab the latest `Harbor.app.zip` from [Releases](https://github.com/eehnsio/Harbor/releases), unzip, and drag to `/Applications`.

> On first launch, right-click → Open to bypass Gatekeeper (the app is not notarized).

### Build from source

Requires Xcode 16+ and `xcodegen` (`brew install xcodegen`). Then `xcodegen generate && xcodebuild -scheme Harbor -configuration Release build`.

## Requirements

- macOS 14+
- Xcode 16+ (to build from source)

## Support

If you find Harbor useful, consider [buying me a coffee](https://buymeacoffee.com/eehnsio).

## License

[MIT](LICENSE)
