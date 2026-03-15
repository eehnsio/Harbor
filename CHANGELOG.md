# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

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
