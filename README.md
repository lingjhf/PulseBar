# PulseBar

PulseBar is a lightweight macOS menu bar monitor for CPU, memory, and network activity. It runs as a status bar app without a Dock icon and keeps the menu bar display compact enough for daily use.

## Features

- CPU usage, memory usage, and live upload/download speed.
- Daily upload/download totals, reset by local calendar day.
- Configurable menu bar fields: CPU, memory, and network can be shown or hidden.
- Display formats:
  - `Standard`: `CPU 12%  MEM 8.0G  ↑117.2K ↓2.0M`
  - `Compact`: `12%  8.0G  ↑117.2K ↓2.0M`
  - `Network Only`: `↑117.2K ↓2.0M`
- Fixed-width menu bar title to reduce width changes while network speed updates.
- `Launch at Login` support through `SMAppService.mainApp`.
- No third-party dependencies.

## Menu

Click the PulseBar item in the macOS menu bar to change what is shown:

- `Show CPU`
- `Show Memory`
- `Show Network`
- `Launch at Login`
- `Display Format`
- `Quit PulseBar`

## Implementation Notes

PulseBar samples system metrics roughly once per second.

- CPU is calculated from host processor tick deltas.
- Memory uses `host_statistics64`, counting internal, wired, and compressed pages as used memory.
- Network speed uses `getifaddrs` byte counters from active non-loopback interfaces.
- Daily network totals are persisted in `UserDefaults` as counter snapshots.
- Preferences are persisted with `UserDefaults`.

## Requirements

- macOS 26.5 or later, matching the current project deployment target.
- Xcode capable of building the configured macOS SDK.

## Development

Run unit tests:

```bash
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild test -project PulseBar.xcodeproj -scheme PulseBar -destination 'platform=macOS,arch=arm64' -only-testing:PulseBarTests
```

Build the app:

```bash
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild build -project PulseBar.xcodeproj -scheme PulseBar -destination 'platform=macOS,arch=arm64'
```

## Release

GitHub Actions builds a release DMG when a plain Semantic Version tag is pushed:

```bash
git tag 1.0.0
git push origin 1.0.0
```

The release workflow builds `PulseBar.app`, packages it into `PulseBar-<tag>.dmg`, writes a SHA-256 checksum, and creates a GitHub Release with both files attached.

The workflow uses the `macos-26` GitHub Actions runner because PulseBar currently targets macOS 26.5.

The CI build uses ad-hoc signing and does not notarize the app. A downloaded release may still show the normal macOS warning for apps that are not Developer ID signed and notarized.

## Notes

For a stable `Launch at Login` registration while testing manually, run PulseBar from a stable app path such as `/Applications/PulseBar.app` instead of an Xcode DerivedData path.
