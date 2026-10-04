# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [1.3.0] - 2026-10-04

### Added

- Docker ports show the container behind them, grouped by compose project (e.g. "db (postgres)")
- Servers whose terminal has been closed get a subtle dot and are marked "detached" in their submenu
- Submenu shows which app a server was started from (Ghostty, Claude, VS Code, …)
- Signed with Developer ID and notarized — no more Gatekeeper workaround

### Changed

- Ports are scanned when the menu opens instead of every 5 seconds (no background CPU use)
- Internal/ephemeral ports are hidden when the project already has a real dev port
- Better names for Node tools run from `node_modules` (e.g. "wrangler" instead of "node cli.js")
- The updater only installs updates signed by the Harbor developer

### Fixed

- Framework detection no longer matches folder names (a project in `honest-app/` is not "nest")
- App bundle was missing `CFBundleIdentifier`

## [1.2.0] - 2026-05-14

### Added

- Per-process submenu with Copy URL, Open in Browser, Terminate, and Force Kill actions
- Launch at Login toggle
- Auto-update via GitHub Releases (in-place check without closing the menu)
- About Harbor window with version info and GitHub/support links
- Custom menu bar icon and pier-themed app icon

### Changed

- Subtle gray hover highlight instead of system blue selection color

## [1.0.0] - 2025-03-15

### Added

- Native port scanning via `libproc` APIs with `lsof` fallback
- Project grouping based on process working directory
- Process display names resolved from command-line args (e.g. `node` -> "next dev", "astro dev")
- Uptime and memory usage per process
- Kill button on hover (SIGTERM with privilege escalation fallback)
- Smart filtering: hides debug ports (9229/9230) and ephemeral ports by default
- "Show All Ports" toggle to reveal filtered ports
- Click-to-open: click a port row to open `http://localhost:<port>` in browser
- IPv4/IPv6 listener deduplication
- Git commit hash shown in menu for version tracking
- Auto-refresh every 5 seconds
