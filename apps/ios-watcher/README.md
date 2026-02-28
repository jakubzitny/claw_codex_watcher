# Watcher iOS Module

Native iPhone + CarPlay companion app for this monorepo's watcher backend.

## Included

- `WatcherIOS` iOS application target (Swift + SwiftUI)
- CarPlay list/detail templates driven by live thread data
- Shared watcher networking/store layer (REST + WebSocket)
- `WatcherIOSTests` unit tests (configuration, API client, store behavior)
- `WatcherIOSUITests` UI smoke tests

## Requirements

- Xcode 26.1+
- iOS Simulator runtime installed from Xcode Components
- `xcodegen` only needed when regenerating project files

## Quick Start

```bash
cd apps/ios-watcher
pnpm gen
pnpm build
pnpm test:unit
```

Open in Xcode:

```bash
open WatcherIOS.xcodeproj
```

## Runtime Configuration

By default the app points to `http://127.0.0.1:18000`.

- For iOS Simulator: keep backend on your Mac, default works.
- For physical iPhone: set Settings -> Watcher Server to your Mac LAN IP, for example `http://192.168.1.100:18000`.
- If backend auth is enabled (`WATCHER_AUTH_TOKEN`), set token in app Settings.

## CarPlay Notes

- Launch iOS simulator, then enable CarPlay simulator from Xcode (`Window > Show CarPlay Simulator`).
- CarPlay root shows active threads and connection mode.
- Selecting a thread pushes summary, plan progress, recent messages, and tool calls.
- Real CarPlay deployment still requires Apple-approved CarPlay entitlements for your app category; this module wires the scene + templates so simulator/dev flow is ready.

## CLI Scripts

- `pnpm build`: simulator build validation
- `pnpm test`: full unit + UI test run
- `pnpm test:unit`: unit tests only
- `pnpm test:ui`: UI tests only

If runtime is missing, scripts fail fast with guidance.
