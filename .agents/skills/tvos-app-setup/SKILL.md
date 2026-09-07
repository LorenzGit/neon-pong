---
name: tvos-app-setup
description: Scaffold a tvOS app from nothing and get it running on a real Apple TV — XcodeGen project, layered parallax app icon and top shelf images generated from code, launch image, signing with a personal team, device pairing and registration, and install via devicectl. Use when starting an Apple TV app, when asked "install this on my Apple TV", or when hitting "no profiles were found", "your team has no devices" or asset catalog slot warnings.
---

# tvOS app setup

## Runtime first

The tvOS simulator runtime is not installed with Xcode by default:

```bash
xcodebuild -showsdks | grep -i tvos
xcodebuild -downloadPlatform tvOS          # ~4 GB, do this early
xcrun simctl list devices available | grep "Apple TV"
xcrun simctl boot <UDID>
```

## Project from a file, not a wizard

XcodeGen keeps the project reviewable and regenerable. `brew install xcodegen`,
then a `project.yml`:

```yaml
name: MyApp
options:
  deploymentTarget: { tvOS: "17.0" }
configs: { Debug: debug, Release: release }
settings:
  base:
    TARGETED_DEVICE_FAMILY: "3"       # 3 = Apple TV
    DEVELOPMENT_TEAM: XXXXXXXXXX
    CODE_SIGN_STYLE: Automatic
  configs:
    Debug:   { SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG }
    Release: { SWIFT_ACTIVE_COMPILATION_CONDITIONS: "" }
targets:
  MyApp:
    type: application
    platform: tvOS
    sources: [Sources, {path: Resources, excludes: ["Info.plist"]}]
    info:
      path: Resources/Info.plist
      properties:
        GCSupportsControllerUserInteraction: true
        GCSupportedGameControllers:
          - { ProfileName: ExtendedGamepad }
          - { ProfileName: MicroGamepad }
    settings:
      base:
        ASSETCATALOG_COMPILER_APPICON_NAME: "App Icon & Top Shelf Image"
```

XcodeGen does **not** set `DEBUG` for you. Declare
`SWIFT_ACTIVE_COMPILATION_CONDITIONS` per config or every `#if DEBUG` block
vanishes and you get "cannot find X in scope".

Keep a fast inner loop that skips the build system entirely:

```bash
SDK=$(xcrun --sdk appletvsimulator --show-sdk-path)
xcrun --sdk appletvsimulator swiftc -typecheck \
  -target arm64-apple-tvos17.0-simulator -sdk "$SDK" $(find Sources -name '*.swift')
```

Seconds instead of minutes, and it catches almost everything.

## The app icon is a layered stack

tvOS icons parallax, so they are not one image. The catalog wants:

```
App Icon & Top Shelf Image.brandassets/
  App Icon.imagestack/              400x240 @1x,2x
    Front.imagestacklayer/Content.imageset/
    Middle.imagestacklayer/…
    Back.imagestacklayer/…
  App Icon - App Store.imagestack/  1280x768 @1x,2x
  Top Shelf Image.imageset/         1920x720 @1x,2x
  Top Shelf Image Wide.imageset/    2320x720 @1x,2x
```

Layers are listed **front to back** in the imagestack's `Contents.json`. Back is
opaque; Front and Middle carry alpha.

Rendering these from code (Core Graphics in a small `swift` script) beats hand
export: one composition function drawn per layer, regenerable after any brand
tweak, and no binaries to diff. Split it as background/grid, then mid-ground
objects, then subject and wordmark — the parallax separation is the point.

Keep content ~11% inside the edges; tvOS crops toward the corners on focus.

## Launch image, and why not a storyboard

tvOS deprecated `UILaunchImages` in favour of a launch storyboard, but **`ibtool`
cannot compile storyboards in a headless session** — it fails with exit 255 and
no diagnostics, even for a minimal file, so any CI or agent-driven build breaks.
The launch image still works on current tvOS:

```
LaunchImage.launchimage/  →  ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME
{ "extent": "full-screen", "idiom": "tv", "minimum-system-version": "9.0",
  "orientation": "landscape", "scale": "1x" }
```

Provide **1x only** at 1920×1080. Adding a 2x entry produces "the launch image
set has an unassigned child" — the slot does not exist. You are left with two
deprecation warnings and a working branded first frame.

## Getting onto the device

Three things must be true, and the errors name them precisely.

**1. An Apple ID in Xcode.** Without it: `error: No Accounts: Add a new account
in Accounts settings`. This step is interactive (Xcode ▸ Settings ▸ Accounts);
nothing on the command line substitutes for it. Verify afterwards:

```bash
defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists
```

**2. The Apple TV paired.** On the device: Settings ▸ Remotes and Devices ▸
Remote App and Devices. In Xcode: Window ▸ Devices and Simulators, Pair, type the
six-digit code. Same network. Then it shows up:

```bash
xcrun devicectl list devices
```

**3. The device registered on the account.** Pairing is not registration.
`-allowProvisioningUpdates` alone gives `Device "X" isn't registered in your
developer account`, or `Your team has no devices from which to generate a
provisioning profile` if you have no Apple TV registered at all. The flag you
want is:

```bash
xcodebuild -project MyApp.xcodeproj -scheme MyApp -configuration Debug \
  -destination "platform=tvOS,id=$ATV" -derivedDataPath build/DDdev \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```

Then install and launch without opening Xcode:

```bash
xcrun devicectl device install app --device "$ATV" path/to/MyApp.app
xcrun devicectl device process launch --device "$ATV" com.example.myapp
xcrun devicectl device info processes --device "$ATV" | grep MyApp   # still alive?
```

There is **no "trust this developer" step on tvOS** — that Settings pane is
iOS-only. A development-signed tvOS app launches straight away.

## Free versus paid team

Check before promising anyone a timeline. A wildcard App ID (`TEAMID.*`) and a
one-year profile expiry mean a paid membership: the build lasts a year. A free
personal team gets explicit bundle IDs only and 7-day expiry.

```bash
security cms -D -i profile.mobileprovision > /tmp/p.plist
/usr/libexec/PlistBuddy -c "Print :ExpirationDate" /tmp/p.plist
/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" /tmp/p.plist
```

## Screenshots and video from the simulator

```bash
# env vars reach the app with a SIMCTL_CHILD_ prefix
env SIMCTL_CHILD_MYAPP_SCENE=result xcrun simctl launch "$DEV" com.example.myapp
xcrun simctl io "$DEV" screenshot --type=png shot.png
xcrun simctl io "$DEV" recordVideo --codec h264 out.mp4 &   # kill -INT to stop
```

Grabs come out at the device's native 3840×2160. Downscale before storing.
