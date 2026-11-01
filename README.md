# OBD-II Dashboard Pro — Phase 1

Native iOS (Swift 5, UIKit, MVVM) automotive digital-cockpit dashboard for
iPad mini 3 (iOS 12.5.8, jailbroken via Amethyst/Procursus), targeting a
Ford Escape 2009 XLT 2.3L 4WD via an ELM327 Bluetooth OBD-II adapter.

**This is Phase 1 only**: dashboard UI + a DEMO MODE telemetry simulator.
There is no Bluetooth/ELM327/real OBD-II code yet — that's Phase 2 onward.
Every value on screen right now is synthetic and labeled `DEMO MODE`.

## What's implemented

- Full MVVM module skeleton per the architecture spec (`Core/`, `Models/`,
  `ViewModels/`, `Views/`, `Simulator/`).
- `OBDSimulator`: a background-queue driving-cycle generator (idle → accel
  → cruise → decel → stop) emitting fast-tick (speed/RPM/throttle/load) and
  slow-tick (coolant/voltage/fuel/intake/ambient/MAF/fuel-rate) telemetry,
  mirroring the priority-polling architecture the real OBD engine will use.
- Dashboard screen: header (logo, BT/ECU status, vehicle name, clock),
  analog speedometer + tachometer gauges (Core Graphics/CAShapeLayer,
  update without full-view redraws), a 2×3 parameter grid (coolant,
  voltage, fuel consumption, avg consumption, engine load, throttle), and
  a footer (trip distance/time/fuel used, connection status).
- 7-tab navigation shell (`UITabBarController`): Dashboard, Live Data, Fuel
  Economy, Diagnostic, Trip Computer, Vehicle Information, Settings. The
  other six are placeholder screens stating which phase implements them.
- Settings screen: vehicle profile (name, displacement, fuel type), speed/
  temperature units, night mode, power-save flag, demo-mode toggle — all
  persisted via `SettingsStore` (UserDefaults + JSON).
- `VehicleProfile` is fully data-driven (no hardcoded Ford Escape constants
  in any calculation) — the shipped default profile just happens to match
  the target vehicle.
- Dark, always-on cockpit theme (`Core/Theme/Theme.swift`) with a red-tinted
  night-mode palette; landscape-only, full-screen (no Split View), status
  bar hidden.

## Project layout

```
OBD2Dashboard/
  project.yml              XcodeGen spec (generates the .xcodeproj)
  App/                      AppDelegate, RootTabBarController
  Core/
    Theme/                  Color/font palette
    Storage/                SettingsStore (UserDefaults persistence)
    Utility/                Observable<T> binding primitive
  Models/                   VehicleProfile, TelemetrySnapshot, AppSettings, enums
  ViewModels/               DashboardViewModel
  Views/
    Dashboard/               Header, footer, main view controller
    Gauges/                  GaugeView (speedometer/tachometer)
    Common/                  ParameterTileView, StatusPillView, DemoModeBadge, PlaceholderViewController
    LiveData/, FuelEconomy/, Diagnostic/, TripComputer/, VehicleInfo/, Settings/
  Simulator/                OBDSimulator (DEMO MODE data generator)
  Resources/                Info.plist, Assets.xcassets, LaunchScreen.storyboard
  Tests/                    XCTest target (Phase 1 smoke tests)
```

## Building (requires macOS + Xcode — not possible from this Windows machine)

This project was scaffolded on Windows, which has no Swift/Xcode toolchain,
so **none of this code has been compiled yet**. Build it on a Mac:

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
2. From the `OBD2Dashboard/` directory: `xcodegen generate`
3. Open `OBD2Dashboard.xcodeproj` in **the latest Xcode you have**. Homebrew
   always installs XcodeGen's latest release, which writes the `.pbxproj`
   in whatever file format that release currently defaults to — if your
   installed Xcode is noticeably older than the XcodeGen release, it may
   refuse to open the project ("future Xcode project file format"). If
   that happens, either update Xcode or pin an older XcodeGen release that
   matches your Xcode's supported format.
4. Select the `OBD2Dashboard` scheme, an iPad simulator or device, and run.
   Code signing is disabled in `project.yml` (`CODE_SIGNING_REQUIRED: NO`)
   so it builds unsigned — fine for simulator/jailbroken-device sideload,
   but a real Apple Developer signing identity is needed for a normal
   (non-jailbroken) device install.
5. Run tests: `xcodebuild test -scheme OBD2Dashboard -destination 'platform=iOS Simulator,name=iPad (10th generation)'`
   (substitute whatever simulator you have; an iPad mini 3-equivalent
   screen size — 1024×768 pt — is closest to `iPad (6th generation)` /
   `iPad (9th generation)` in modern simulators, since iPad mini 3 itself
   isn't available as an Xcode 15 simulator device).

## What's deliberately NOT here yet

- Any Bluetooth code (`CoreBluetooth`, `BluetoothTransport` abstraction) —
  Phase 2. The adapter's actual Classic SPP vs BLE behavior, service/char
  UUIDs, and write type still need to be verified against the real ELM327
  hardware before that code is written, per spec section 2.
- The real `OBDEngine` / PID decoder / Mode 01-0A command handling — Phase 3.
- The real Fuel Consumption Engine (ECU PID 5E vs MAF-derived vs estimated,
  with source-confidence display) — Phase 4. The Phase 1 dashboard's fuel
  tiles are an inline simulator-only preview of the display *rules*, not
  the engine itself.
- DTC scan/clear — Phase 5.

## CI

`.github/workflows/ios-build.yml` runs on every push/PR on a `macos-14`
GitHub-hosted runner: installs XcodeGen, generates the project, builds the
unsigned ARM64 device target, runs the XCTest suite on an iPad simulator,
then archives and uploads an unsigned `.ipa` as a build artifact. This is
the only way to get real build/test feedback on this project right now,
since it was authored on a Windows machine with no Swift/Xcode toolchain.

## Known constraint

Minimum deployment target is iOS 12.0, so this code deliberately avoids:
Combine, SwiftUI, SF Symbols, `UIScene`/`SceneDelegate`, and any other
iOS 13+-only API. The MVVM bindings use a hand-rolled `Observable<T>`
closure wrapper instead of Combine for this reason.
