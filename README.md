# 3Fingers

A tiny open-source menu bar daemon for Apple Silicon Macs that turns a **3-finger tap** or **3-finger click** on the trackpad into a **middle click** (mouse button 3, `CGEvent` button 2) at the cursor.

**Website:** https://mpalarya.github.io/3Fingers/

Use it to open links in new tabs, close browser tabs, paste in terminals, and do anything else that needs a middle mouse button.

- Apple Silicon (`arm64`) only, macOS 14 Sonoma or later
- Menu bar only: no Dock icon, no windows
- Native Swift with no dependencies. Built with Swift Package Manager

## Install

### Homebrew

```sh
brew tap mpalarya/3fingers https://github.com/MPalarya/3Fingers
brew trust mpalarya/3fingers
brew install --cask 3fingers
```

Homebrew 7 and later require you to trust a third-party tap before installing from it (`brew trust`).

To upgrade, run `brew upgrade` (the cask is bumped automatically on every release). To remove it, run `brew uninstall --cask 3fingers`.

### curl

```sh
curl -fsSL https://raw.githubusercontent.com/MPalarya/3Fingers/main/install.sh | bash
```

This downloads the latest release, installs it into `/Applications` and launches it. Run the same command again to update.

Both methods skip the Gatekeeper warning described below. After installing, grant **Accessibility** access when asked (step 4).

### Manual

1. Download `3Fingers.dmg` from the [latest release](../../releases/latest).
2. Open the DMG and drag **3Fingers** into **Applications**.
3. Launch it. See the next section to get past Gatekeeper.
4. When asked, grant **Accessibility** access in *System Settings → Privacy & Security → Accessibility*. 3Fingers needs this to post and rewrite mouse clicks. It picks up the permission on its own, so you don't have to relaunch.

### Opening an unnotarized app (Gatekeeper)

Release builds are ad-hoc signed but not notarized by Apple, so macOS blocks them the first time you open them.

**macOS 14 Sonoma:**

1. In Finder, **Right-click** (or Control-click) `3Fingers.app` in Applications and choose **Open**.
2. In the dialog that appears, click **Open**. macOS remembers this choice, and later launches work normally.

**macOS 15 Sequoia and later:** Right-click → Open no longer bypasses Gatekeeper. Instead:

1. Double-click `3Fingers.app`. When the warning appears, click **Done**.
2. Open *System Settings → Privacy & Security* and scroll down to the message about 3Fingers.
3. Click **Open Anyway** and confirm with your password or Touch ID.

**Any version, from Terminal:**

```sh
xattr -dr com.apple.quarantine /Applications/3Fingers.app
```

## Usage

The hand icon in the menu bar has three options:

| Item | What it does |
| --- | --- |
| **Enabled** | Turns gesture detection on or off. The setting is remembered. Turning it off and on again also re-scans for trackpads, for example after you connect a Magic Trackpad. |
| **Launch at Login** | Registers the app with `SMAppService.mainApp`. |
| **Quit 3Fingers** | Quits the app. |

If Accessibility access is missing, the menu also shows **Grant Accessibility Access…**.

### How gestures are recognized

| Gesture | Rule |
| --- | --- |
| 3-finger tap | The finger count goes 0 → 3 → 0, with a peak of exactly 3. The whole touch must last **< 180 ms**, and no finger may move more than **2% of the trackpad's size** (normalized coordinates). |
| 3-finger click | A physical click while exactly 3 fingers are down is rewritten in flight into a middle click, so no left click gets through. |
| Debounce | No second middle click is fired within **250 ms** of the previous one. |

Three-finger swipes, drags and Mission Control or App Exposé gestures take too long or move too far, so they never trigger a click.

**Tip:** If *Trackpad → Point & Click → Look up & data detectors* is set to *Tap with Three Fingers*, change it to *Force Click with One Finger*. Otherwise both actions fire. If you use *Three Finger Drag* (an Accessibility setting), you will usually want to turn it off as well.

## Logs and debugging

Everything is logged with `os.Logger` (subsystem `com.3fingers.app`, category `GestureEngine`):

```sh
log stream --predicate 'subsystem == "com.3fingers.app"'
```

Clicks that fire and lifecycle events are logged at the default level. To also see *why* a gesture was rejected (duration, displacement, finger count, debounce), add `--level info`:

```sh
log stream --level info --predicate 'subsystem == "com.3fingers.app"'
```

## Build from source

You need Xcode 15+ or the Command Line Tools on an Apple Silicon Mac.

```sh
swift build -c release --arch arm64     # just the binary
scripts/build_app.sh                    # -> build/3Fingers.app (ad-hoc signed)
scripts/make_dmg.sh                     # -> build/3Fingers.dmg
```

`VERSION=1.2.3 scripts/build_app.sh` sets the bundle version. `CODESIGN_IDENTITY="Developer ID Application: …"` signs with a real identity instead of ad-hoc.

> **Note:** With ad-hoc signing, every rebuild gets a new code signature, and macOS treats it as a different app. After rebuilding, remove 3Fingers from the Accessibility list and add it again.

### Releasing

Push a tag that starts with `v`:

```sh
git tag v1.0.0 && git push origin v1.0.0
```

`.github/workflows/release.yml` then builds the arm64 app on a `macos-15` runner, packages `3Fingers.dmg`, and attaches it to a GitHub Release for that tag.

## How it works

- **`Multitouch.swift`** loads the private `MultitouchSupport.framework` at runtime with `dlopen`/`dlsym`, so nothing private is linked. It enumerates devices with `MTDeviceCreateList` and registers a contact-frame callback on each one. Devices are re-enumerated after the Mac wakes from sleep.
- **`CMultitouch`** is a header-only C target that declares the reverse-engineered `MTTouch` struct (96 bytes).
- **`GestureEngine.swift`** runs the tap state machine for each device on the framework's thread. It posts synthesized `otherMouseDown`/`otherMouseUp` events with button 2, and owns the `CGEventTap` that rewrites 3-finger physical clicks.
- **`AppDelegate.swift`** handles the menu bar UI, the Accessibility prompt (`AXIsProcessTrustedWithOptions`) and Launch at Login (`SMAppService.mainApp`).

`MultitouchSupport` is a private API, so a future macOS update could break it.

## License

MIT
