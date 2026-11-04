# OBD-II Dashboard Pro

Native iOS (Swift 5, UIKit, MVVM) digital cockpit for iPad mini 3 (iOS 12.5.x)
and a BLE ELM327 OBD-II adapter. Built for a Ford Escape 2009 XLT 2.3L 4WD, but
`VehicleProfile` is data-driven, so no calculation hardcodes that vehicle.

Every value on screen comes from the vehicle. There is no demo mode or
simulated data.

## Screens

- **Dashboard:** speedometer, tachometer, coolant, battery voltage, fuel
  consumption, engine load, throttle, and trip summary.
- **Live Data:** every supported PID with its value, data source, session
  min/max and trend line, plus CSV recording and export.
- **Fuel Economy:** instantaneous, current-trip and since-reset consumption.
- **Diagnostic:** stored, pending and permanent trouble codes, and clearing
  them with a confirmation and a re-read to verify.
- **Trip Computer:** current trip and since-reset totals.
- **Vehicle Info:** adapter scan and connect, adapter version, protocol, VIN,
  and the BLE/OBD log (`Copy Log` puts it on the clipboard).
- **Settings:** vehicle profile, units, warning limits, night mode, power save,
  and automatic reconnect.

## Using it

1. Turn the ignition on. The adapter needs a running ECU to answer.
2. In **Vehicle Info**, tap **Scan for Adapters** and pick the adapter. Later
   launches reconnect to it automatically for up to 60 seconds.
3. Wait for the ECU status to show `ECU READY`. The protocol search can take up
   to 10 seconds, and init retries once.

If the ECU status shows `ERROR`, the log in **Vehicle Info** has each command
sent, the raw reply, and the reason. `UNABLE TO CONNECT` usually means the
adapter is not plugged in or the ignition is off.

CSV logs are written to the app's Documents folder, visible in the Files app,
and hold one sample per second in metric units.

## Project layout

```
App/          AppDelegate, RootTabBarController
Core/
  Bluetooth/  BLETransport, BluetoothManager
  OBD/        ELM327Initializer, OBDEngine, OBDRequestQueue, OBDResponseParser
  PID/        PID table, decoding, display units
  Fuel/       FuelConsumptionEngine, TripComputer
  Diagnostic/ DTC parsing, library and engine
  Telemetry/  TelemetryHub, TelemetryCSVLogger
  Storage/    SettingsStore
Models/       Settings, telemetry, vehicle profile and connection types
ViewModels/   Dashboard and Live Data view models
Views/        One folder per screen, plus shared gauges and tiles
Tests/        XCTest suite, including a scripted adapter
```

## Building

There is no Swift toolchain on the Windows machine this is developed on, so CI
is the build. `.github/workflows/ios-build.yml` runs on every push: it generates
the project with XcodeGen, builds for ARM64, runs the tests on an iPad simulator,
and uploads an unsigned `.ipa`. Pushes to `main` also publish it as a public
GitHub Release tagged `ci-<run>`.

On a Mac: `brew install xcodegen`, `xcodegen generate`, then open the project.
Tests run with `xcodebuild test -scheme OBD2Dashboard -destination
'platform=iOS Simulator,name=iPad (10th generation)'`.

## Installing on the iPad

The IPA is unsigned on purpose, because Sideloadly and AltStore re-sign it.

1. Download `OBD2Dashboard-unsigned.ipa` from the newest release or CI run.
2. Install Apple's **Apple Devices** app, or iTunes from apple.com rather than
   the Microsoft Store build.
3. Open Sideloadly, drag in the IPA, enter an Apple ID, and start. With
   two-factor authentication on, use an app-specific password.
4. On the iPad, trust the certificate under Settings → General → Profiles &
   Device Management.

A free Apple ID is enough, but the signature expires after 7 days, so the app
needs re-signing weekly.

Sideloadly may append the team ID to the bundle ID, which gives the app a new
data container and resets its settings and trip totals.

## Known limitations

- **BLE scanning returns nothing while the iPad is jailbroken with Amethyst.**
  CoreBluetooth reports `isScanning=true` with zero discoveries, while nRF
  Connect finds devices on the same iPad, and this app scans normally when the
  iPad is not jailbroken. **Use the app without the jailbreak active.**
  Tested without effect: removing tweaks and Sonar injection, restarting
  `bluetoothd`, `AllowDuplicates`, a matching bundle ID, and removing
  `get-task-allow`. The root cause is not known. The remaining suspects are
  `base_hook.dylib` and the jailbreak core treating self-signed apps differently
  from App Store apps.
- **BLE adapters only.** Classic Bluetooth SPP adapters are out of reach of
  CoreBluetooth. They would need another `BluetoothTransport` over
  ExternalAccessory/MFi.
- **The adapter UUIDs are not editable in the app** (`FFF0`, write `FFF2`, notify
  `FFF1`). They are stored settings, but `CBUUID` traps on an invalid string, so
  they need a validated editor before they can be exposed.
- **The trouble code library is small.** Codes outside it are still shown, with
  a generic description.
- **Trip figures are always metric,** whatever the speed unit setting.

## Deployment target

The minimum is iOS 12.0, so the code avoids Combine, SwiftUI, SF Symbols,
`UIScene`, and other iOS 13+ APIs. Bindings use the hand-rolled `Observable<T>`.
