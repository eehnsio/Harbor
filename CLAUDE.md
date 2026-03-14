# Harbor

macOS menu bar app showing listening dev server ports. Native Swift/AppKit, no dependencies.

## Build

- `xcodegen generate` — regenerate `.xcodeproj` from `project.yml` (run after adding/removing files)
- `xcodebuild -project Harbor.xcodeproj -scheme Harbor -configuration Debug build` — build
- `killall Harbor` before rebuilding to avoid code signing conflicts
- Release: build with `-configuration Release`, copy `.app` to `/Applications`

## Architecture

- `AppDelegate.swift` — NSStatusItem + NSMenu (not SwiftUI MenuBarExtra, because NSMenu supports custom NSView items)
- `PortScanner.swift` — libproc API scan with lsof fallback
- `ProcessInspector.swift` — process name, args (sysctl KERN_PROCARGS2), cwd (PROC_PIDVNODEPATHINFO), uptime, memory
- Display names resolved from command-line args (e.g. node → "next dev") and cwd (e.g. "/Users/erik/Developer/walle" → "walle / vite")

## Gotchas

- `insi_lport` from libproc is `Int32` not `UInt16` — use `UInt16(truncatingIfNeeded:)`
- SwiftUI `\(someUInt16)` adds locale thousands separator — use `String(value)` for port numbers
- SwiftUI Menu items ignore HStack/Spacer — use NSView-based menu items for custom layout
- `@MainActor` required on AppDelegate class for PortViewModel access
