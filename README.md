# OBD-II Dashboard Pro

Native iOS (Swift 5, UIKit, MVVM) automotive digital-cockpit dashboard for
iPad mini 3 (iOS 12.5.x, jailbroken via Amethyst/Procursus), targeting a
Ford Escape 2009 XLT 2.3L 4WD via an ELM327 Bluetooth OBD-II adapter.

Phases 1–5 are implemented: dashboard UI and DEMO MODE simulator, the
CoreBluetooth transport, the ELM327 init sequence and OBD request queue,
PID decoding, the fuel-consumption engine and trip computer, and DTC
scan/clear. `demoModeEnabled` defaults to `true`, so every value on screen
is synthetic and labeled `DEMO MODE` until you turn demo mode off in
Settings and connect a real adapter.

**Current blocker:** CoreBluetooth returns an empty scan list on the
target device. See "Installing on the iPad" for the diagnosis and fix.

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
   so it builds unsigned. That is deliberate, and it is the *correct* input
   for Sideloadly/AltStore — both strip whatever signature is present and
   re-sign with your own identity. See "Installing on the iPad" below; do
   not install the unsigned IPA directly via AppSync Unified, as that path
   is what the Bluetooth investigation implicates.
5. Run tests: `xcodebuild test -scheme OBD2Dashboard -destination 'platform=iOS Simulator,name=iPad (10th generation)'`
   (substitute whatever simulator you have; an iPad mini 3-equivalent
   screen size — 1024×768 pt — is closest to `iPad (6th generation)` /
   `iPad (9th generation)` in modern simulators, since iPad mini 3 itself
   isn't available as an Xcode 15 simulator device).

## Installing on the iPad (signed with a free Apple ID)

**Install this way, not via AppSync Unified.** CoreBluetooth on the target
iPad returns an empty scan list for this app while `Settings.app` still
discovers Classic devices normally. Entitlement variations (no-sandbox,
platform-application, get-task-allow, dev-signing-style), `uicache -s`,
`CBCentralManagerScanOptionAllowDuplicatesKey` and a full reboot all made
no difference. The leading hypothesis is that `bluetoothd` applies its own
client-signature trust check, separate from AMFI's launch-time check, that
an `ldid`-only ad-hoc signature fails regardless of entitlement content —
AppSync bypasses the *launch* check but never produces a real certificate
chain. Signing with a genuine identity is both the fix and the experiment
that confirms the diagnosis.

A free Apple ID is enough. No paid Developer Program membership is needed:
CoreBluetooth central-role scanning requires no special entitlement, so
nothing this app uses is restricted on a free provisioning profile.

### Sideloadly (recommended — this project is developed on Windows)

1. Download `OBD2Dashboard-unsigned.ipa` from the newest `ci-*` GitHub
   Release (see "CI" below).
2. **Delete any existing copy of the app from the iPad first.** It shares
   the bundle ID `com.diy.obd2dashboard.app`. If the old AppSync-installed
   build is left in place, the install can keep the previous binary and
   container — you would conclude signing made no difference without
   having actually tested it.
3. Install Apple's **Apple Devices** app, or iTunes downloaded from
   apple.com — *not* the Microsoft Store build, which does not expose the
   device drivers these tools need.
4. Open Sideloadly, drag in the IPA, enter the free Apple ID, Start. With
   two-factor authentication on the account, use an app-specific password
   generated at appleid.apple.com, not the account password.
5. On the iPad: Settings → General → **Profiles & Device Management** (the
   iOS 12 wording; it is "VPN & Device Management" on newer iOS) → trust
   the developer certificate. The app will not launch until you do.

### AltStore (alternative)

AltStore needs iOS 12.2+; this device runs 12.5.x, so it qualifies. It
requires AltServer running on the PC plus the same non-Microsoft-Store
iTunes, and it refreshes apps over Wi-Fi while AltServer is reachable.
Sideloadly is the simpler path on Windows, so prefer it unless you
specifically want AltStore's refresh behaviour.

### The 7-day expiry, and why the jailbreak helps here

Free-account certificates expire after 7 days (limits: 3 sideloaded apps
at a time, 10 App IDs per 7 days). Re-running Sideloadly weekly works but
needs the PC and a cable each time.

Because this iPad is jailbroken, **ReProvision Reborn** is the better
long-term answer: it re-signs installed apps on-device using the same free
Apple ID and renews them automatically, with no weekly tether. Note that
it solves only the *expiry* problem — the app must still have been
installed with a real signing identity in the first place, which is what
the steps above do.

### Confirming the diagnosis

Open the **Vehicle Info** tab, tap **Scan**, wait 30s, and read the live
BLE log panel beside the device list (`Copy Log` puts it on the clipboard;
entries also go to `NSLog`). If `didDiscover` lines now appear where the
AppSync-installed build logged `isScanning=true discovered=0` for the full
30s, the signature was the cause and `Core/Utility/BLELog.swift`'s
commentary should be updated to record that as settled.

## What's deliberately NOT here yet

- A Classic Bluetooth **SPP** transport. `BLETransport` is BLE-only, and
  CoreBluetooth cannot reach SPP adapters at all — that would need a
  separate `BluetoothTransport` conformer over ExternalAccessory/MFi. Not
  currently needed: the adapter was confirmed to be genuine BLE (service
  FFF0, characteristics FFF1/FFF2) with LightBlue. Note that this was read
  on a *different* device, so it says nothing about whether CoreBluetooth
  works on the iPad itself — see `Models/AppSettings.swift`.
- Verification of any of this against the real vehicle. Nothing beyond the
  BLE scan has been exercised end-to-end on the car, because the scan is
  still the blocker.

## CI

`.github/workflows/ios-build.yml` runs on every push/PR on a `macos-14`
GitHub-hosted runner: installs XcodeGen, generates the project, builds the
unsigned ARM64 device target, runs the XCTest suite on an iPad simulator,
then archives and uploads an unsigned `.ipa`. On pushes to `main` it also
publishes that IPA as a public GitHub Release asset tagged `ci-<run>`,
downloadable without a logged-in GitHub session (workflow-run artifacts
are not). This is the only way to get real build/test feedback on this
project, since it was authored on a Windows machine with no Swift/Xcode
toolchain.

The IPA is unsigned on purpose: Sideloadly and AltStore re-sign from
scratch, so an unsigned archive is the right input. It is **not** meant to
be installed directly via AppSync Unified — see "Installing on the iPad".

## Known constraint

Minimum deployment target is iOS 12.0, so this code deliberately avoids:
Combine, SwiftUI, SF Symbols, `UIScene`/`SceneDelegate`, and any other
iOS 13+-only API. The MVVM bindings use a hand-rolled `Observable<T>`
closure wrapper instead of Combine for this reason.
