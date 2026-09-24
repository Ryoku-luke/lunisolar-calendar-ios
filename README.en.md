**Language / 语言：** [简体](README.md) | [繁體](README.zh-Hant.md) | English | [日本語](README.ja.md)

# Qinghe Calendar · iOS Chinese Lunar Calendar

> 「清和」(Qinghe) originates from the *Book of Han* — "天气清和，稼穑咸秀" (clear and gentle weather, thriving harvests) — evoking calm, warm days and a beautiful life.

A calendar app for iOS / iPadOS with Gregorian↔Lunar conversion, traditional almanac (黄历), events/notes/reminders, weather, countdown Live Activities, local notifications, and iCloud sync. The interface follows iOS 26/27 design language (Liquid Glass + festive adaptive accent colors + press feedback), adapts to iPhone / iPad layouts, and is verified compatible with iOS 27 / iPadOS 27.

## Features

| Module | Description |
|---|---|
| Month view | 7-column grid, card-style swipe between months, "Today" shortcut, tappable month title picker, long-press context menu on date cells |
| Year overview | 12 mini month grids in one screen; today / events / solar terms / festivals marked; tap a month to jump |
| Chinese lunar calendar | 1900–2100 Gregorian↔Lunar conversion, leap months, sexagenary cycle, zodiac; bidirectional lookup |
| Almanac (黄历) | 宜/忌 (auspicious/avoid), 冲煞, five elements, directions of 财神/喜神; discrete DB (2024–2028) + algorithmic fallback |
| Solar terms & festivals | Terms labeled inline in cells (visible without selection), traditional festival accent colors, official holiday schedule with 休/班 badges |
| Weather | Open-Meteo (no API key) + automatic location + reverse geocoding; shows the selected day's weather inside the date card |
| Event management | Schedule / Reminder / Note types, priority tags, local notifications, recurrence (including **lunar-yearly**) |
| Countdown / anniversary | Anniversary calculation (leap month / Feb 29 fallback), **Live Activity on Dynamic Island + Lock Screen** (system-driven timer, zero battery cost) |
| Data import | System calendar (EventKit) + Contacts import, .ics/.csv/.json restore, deterministic UUID de-duplication |
| iCloud sync | Real CloudKit (private DB + custom zone + tombstones + incremental pull) + Mock test container |
| Widgets | Today's almanac / lunar date card / today's to-do progress; App Group shared snapshot, instant refresh on data change |
| Localization | Simplified Chinese / Traditional Chinese / Japanese / English (including Widgets & Live Activity) |
| Themes | Light/Dark adaptive, configurable week start day, festive icon auto-switch (Spring Festival edition) |
| AI Assistant | On-device natural-language parsing ("tomorrow 3pm remind me to call") → preview → one-tap create; no cloud upload |
| Navigation | iPhone Tab bar (Calendar / Almanac / Me); iPad three-pane Sidebar (Calendar / Year / Countdown / Settings) |

## Requirements

- iOS / iPadOS 17.0+ (Liquid Glass auto-enabled on iOS 26+; verified on iOS 27 / iPadOS 27)
- Swift 6.0 / Xcode 16.0+ (Xcode 27 recommended; App Store submissions require Xcode 27 builds from Q1 2027)

## Running

### Directly with Xcode (recommended)

1. Open `LunisolarCalendar.xcodeproj` in the repo root
2. Select the **LunisolarCalendar** target → Signing & Capabilities → choose your Team
3. Make sure the main app and the Widget extension share the same App Group (<同一 App Group>)
4. ⌘R to run (simulator needs no signing; for a real device, configure the Bundle ID and provisioning profile in the Developer Portal first)

> Full signing / capability guide: [`docs/XCODE_BUILD_GUIDE.md`](docs/XCODE_BUILD_GUIDE.md) and [`docs/ENTITLEMENTS.md`](docs/ENTITLEMENTS.md).

### As a Swift Package

```swift
dependencies: [
    .package(url: "https://github.com/Ryoku-luke/lunisolar-calendar-ios.git", branch: "main")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "LunisolarCalendarApp", package: "lunisolar-calendar-ios")
    ])
]
```

```swift
import SwiftUI
import LunisolarCalendarApp

@main
struct YourApp: App {
    var body: some Scene {
        WindowGroup {
            AdaptiveRootView()
                .environment(EventStore.shared)
        }
    }
}
```

### App Icon

- Icon sources: `Assets/Assets.xcassets/AppIcon.appiconset/` (four-seasons calendar icon) and `AppIconSpringFestival.appiconset/` (Spring Festival edition)
- Regenerate all PNG sizes: `python3 Tools/gen-icons-flat-blue.py` (requires Pillow)
- Auto switch during the Spring Festival window is handled by `AlternateIconManager.shared.applyTodayIfNeeded()`

### Widget Integration

1. The Widget extension's `@main` uses `LunisolarWidgetsBundle()`
2. The main app and Widget extension share the same App Group (<同一 App Group>)
3. On launch the main app sets `EventStore.shared.widgetAppGroupID = appGroupID` (wired in HostApp.swift)
4. Live Activity (Dynamic Island): both the main app and Widget extension Info.plist need `NSSupportsLiveActivities = true`

### iCloud / CloudKit

1. Xcode → Main App Target → Signing & Capabilities → add iCloud → check CloudKit
2. Enable the "iCloud Sync" toggle in Settings

> Free personal developer accounts do not support the iCloud capability (related entitlement keys were removed; the app degrades gracefully to an "unavailable" notice and all other features keep working); Linux / SwiftPM environments use MockCloudKitProvider.

## Project Structure

```
LunisolarCalendar.xcodeproj/     # Xcode host project (entry points + resources only; business code via SwiftPM)
LunisolarHostApp/                # Main app host entry (HostApp.swift + entitlements)
LunisolarWidget/                 # Widget extension host (WidgetMain.swift + Info.plist + entitlements)
Assets/Assets.xcassets/          # App icons (primary + Spring Festival)
Sources/LunisolarCalendarApp/
├── App/                         # @main entry + AdaptiveRootView + appearance preferences
├── Models/                      # LunarDate (lunar algorithm) / Huangli (almanac) / CalendarEvent / CountdownEvent
├── Stores/EventStore.swift      # @Observable + JSON persistence + dirty tracking + Widget snapshot
├── Support/                     # Design tokens, weather, festivals/terms, almanac DB, notifications, import bridges, rating prompt, etc.
├── Sync/                        # CloudKit sync (protocol / Mock / real / coordinator)
├── Widgets/                     # 3 widgets + countdown Live Activity
├── Views/                       # Month view / Year overview / Day detail / Edit / Countdown / Settings / Weather card
└── Resources/                   # lunar_calendar.json, huangli_db.json, 4 lproj localization bundles
Tools/                           # Almanac DB generator + icon generation script
Tests/LunisolarCalendarTests/    # 99 unit tests
UITests/                         # UI smoke tests (3)
docs/                            # App Store / signing / build guides
```

## Build & Test

```bash
swift build        # Build all targets
swift test         # Run 99 unit tests
```

> On Linux only the model layer is verified (lunar/almanac/event CRUD/import-export/sync Mock); SwiftUI views require the iOS/macOS SDK. This repository has **no CI configured** (no `.github/workflows`, so pushing triggers no build). Local checks: `swift build` / `swift test` (macOS host, available since 2026-09-24) plus `swift build --triple arm64-apple-ios17.0-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"` (iOS view layer + host app) — see `docs/XCODE_BUILD_GUIDE.md` §4.

## Test Coverage (99 tests)

| Suite | Count | Covers |
|---|---|---|
| CalendarEventTests | 16 | Event model, lunar recurrence, ICS round-trip, priority, festival color |
| EventStoreTests | 16 | CRUD, search, merge strategy, duplicate protection, toggleCompleted re-scheduling |
| ICloudSyncTests | 11 | Push/pull/conflict/incremental/offline-online/tombstone propagation |
| SystemImportTests | 9 | DTO mapping, deterministic UUID, aggregation, end-to-end no duplicates |
| DataPortabilityTests | 8 | JSON/ICS round-trip, pseudo-UUID stability, merge stats |
| HuangliDBProviderTests | 6 | DB hits, boundary fallback, DB↔algorithm consistency |
| LunarDateTests | 5 | Lunar truth points, leap months, boundary nil-safety, reverse conversion |
| NotificationLunarAnniversaryTests | 5 | Lunar anniversary boundary, leap-month fallback/match |
| HolidayProviderTests | 7 | 2025/2026 official holiday anchors, makeup workdays |
| CountdownEventTests | 7 | Anniversary (this year / year-crossing / Feb 29 fallback), countdown text |
| WidgetSnapshotTests | 4 | Snapshot read/write, expiry, auto-write |
| AccessibilityIDTests | 3 | Accessibility identifier consistency |
| HuangliTests | 2 | 宜/忌 stability, 冲煞 verification |

## Configuration Notes

### Almanac Data Strategy (product decision)

1. **Data source (important — do not overclaim)**: 宜忌 / 冲煞 / 神位 are **derived in-app from a traditional sexagenary-cycle (干支) rule set** (see `yiPool` / `jiPool` in `Models/Huangli.swift`).
   `huangli_db.json` is a **pre-generated result** for 2024-01-01 ~ 2028-12-31 (an offline cache produced by the same rule set, purely for faster loading).
   It is **not a human-verified authoritative almanac**: the bundled DB contains only 9 distinct 「宜」 combinations and 10 distinct 「忌」 combinations across 1,827 days (grouped by the day's heavenly stem) — i.e. coarse rule-derived data.
   Dates outside that range are derived live by the same rule set, so there is never an empty state.
2. **Wording boundaries**: neither in-app copy nor store descriptions may call this data "authoritative" or "verified"; almanac content is for reference only.
3. **In-app visibility**: Settings → Data & Sync → Advanced Data Settings shows the data-provenance note (`HuangliDBProvider.coverageDescription`).
4. **Replacing / extending**: to adopt an authoritative source, replace `huangli_db.json` (keys must stay `yyyy-MM-dd`); when the rule set changes, regenerate via `swift run gen_huangli_db` and spot-check with `HuangliDBProviderTests` before merging.

### Localization (built in)

- 4 `lproj` bundles (zh-Hans / zh-Hant / ja / en) are registered in both the main app and Widget target Resources phases
- Adding a language: copy any `lproj` and translate the key-value pairs — no code changes needed

### UI Tests

- Create a **UI Testing Bundle** target (named `LunisolarCalendarUITests`), Target Application: LunisolarCalendar
- Add `UITests/LunisolarCalendarUITests.swift` to that target, Cmd+U to run 3 smoke tests

## Release Checklist

- [ ] `CFBundleShortVersionString` / `CFBundleVersion` bumped (currently `MARKETING_VERSION = 1.0.1`)
- [ ] Xcode → Product → Archive succeeds (no codesign errors)
- [ ] Main app + Widget extension share the same App Group (<同一 App Group>)
- [ ] iCloud capability enabled and CloudKit container configured (paid account)
- [ ] Privacy usage descriptions (location / contacts / calendar) reviewed
- [ ] App Icon 1024×1024 has no transparency (App Store requirement)
- [ ] Spring Festival alternate icon declarations complete
- [ ] Device tests: notifications → reminder lock-screen alert; iCloud multi-device consistency; Widget snapshot refresh; Live Activity on/off the island
- [ ] Privacy Manifest declared
- [ ] App Store Connect: screenshots, description, keywords, privacy labels filled in

See [`docs/APP_STORE.md`](docs/APP_STORE.md), [`docs/ENTITLEMENTS.md`](docs/ENTITLEMENTS.md) and [`docs/XCODE_BUILD_GUIDE.md`](docs/XCODE_BUILD_GUIDE.md).

## Key Issues Fixed

56+ bugs fixed cumulatively, covering data safety, concurrency races, CloudKit API compatibility, calendar consistency, Swift 6 concurrency isolation, UI touch targets, etc. Key directions:

- **Data safety**: corrupted data no longer overwrites user data; dirty flags persist across restarts; out-of-range dates no longer show "fake lunar" data
- **Concurrency**: serialized push queue, re-entrancy guard, `@MainActor`-isolated coordinator, Swift 6 region-based checker compliance
- **Calendar consistency**: unified `.gregorian` across all modules; correct lunar anniversary / leap-month boundaries
- **Platform adaptation**: iOS 26/27 Liquid Glass native upgrade, new Live Activity APIs, CloudKit deprecated API migration
- **UI/performance**: all interactive elements ≥ 44pt touch targets, O(1) month-grid cache, static `Calendar.gregorian` on hot paths

## License

MIT
