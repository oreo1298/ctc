<!--
SPDX-FileCopyrightText: 2026 Siegefall contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# iOS and iPadOS

The game runs on iPhone and iPad (iOS 15 or newer, 64-bit ARM), landscape
only, with touch controls, safe areas, haptics and auto-pause. There is no App
Store release; you build it yourself and install it on your own device.

## What CI produces

`.github/workflows/packages.yml` exports the Xcode project on Linux (Godot
does not need a Mac for that) and builds it on a macOS runner with signing
switched off. The `ios-unsigned` artifact is an `.ipa` with no signature:
iOS will not install it as it is, but any tool that signs apps with your own
Apple ID can.

## Build it yourself on a Mac

You need Xcode 26 or newer (Godot 4.7's iOS template is built against the
iOS 26 SDK; the app itself still runs on iOS 15) and a free Apple account.

1. Get the Xcode project, either from a Linux machine
   (`make build ARGS="--target ios"`, then copy `build/export/ios/` to the Mac)
   or on the Mac itself:
   ```bash
   make dev
   make build ARGS="--target ios"
   ```
   To have the project signed with your team straight away, set
   `SF_IOS_TEAM_ID` (the 10-character ID from developer.apple.com, under
   Membership) before building. Without it the project uses a placeholder.
2. Open `build/export/ios/Siegefall.xcodeproj` in Xcode.
3. Select the **Siegefall** target → *Signing & Capabilities*, tick
   *Automatically manage signing* and choose your team (a free "Personal
   Team" works). If Xcode says the bundle ID is taken, change
   `io.github.oreo1298.Siegefall` to something unique to you.
4. Plug in the device, choose it as the run destination and press **Run**.
   The first time, allow the developer certificate on the device under
   *Settings → General → VPN & Device Management*.

With a free account the app stops launching after 7 days; build and run it
again to renew. A paid developer account lasts a year.

## Platform details

* **iOS version:** 15 or newer (`application/min_ios_version` in
  `packaging/godot/export_presets.cfg.in`). Every library the app links is
  built for iOS 14 or older: Godot's engine and MoltenVK for 14.0,
  godot-rapier for 12.0. That covers iPhone 6s / SE (1st generation) and
  newer, and iPad (5th generation), iPad mini 4, iPad Air 2 and newer.

* **Display:** landscape left and right, full screen, safe areas respected in
  the HUD, menus and editor (`UiTheme.safe_insets`).
* **Touch:** tap to swing and release, tap in flight for the ammo trick, the
  ammo button cycles ammo, two-finger pan and pinch in the castle editor.
  One-button mode works with a single tap.
* **Haptics:** a short pulse on big impacts (Settings → Play → Vibration).
* **Auto-pause:** leaving the app (home gesture, a call, locking) pauses the
  level.
* **Files:** saves and your castles live in the app's Documents folder, which
  is visible in the Files app under *On My iPhone/iPad → Siegefall*, so castle
  `.json` files can be shared from there. Share codes go through the
  clipboard.
* **Privacy:** no network, no tracking, no permissions requested. The
  manifest `PrivacyInfo.xcprivacy` comes from Godot's template.
* **Physics:** godot-rapier ships an `arm64` iOS framework, which the export
  embeds. (There is no simulator build of it, so the game cannot run in the
  iOS Simulator.)
