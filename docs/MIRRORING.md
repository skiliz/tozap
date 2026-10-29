# Screen Mirroring with ZAP

ZAP's **Mirror** button helps you show your Mac's screen on a Fire TV. ZAP itself does not stream, receive
or process video: macOS sends the picture, and an AirPlay receiver app on the TV shows it.

## Who does what

| Part | What it does | Evidence |
|---|---|---|
| **macOS** | Captures, encodes and sends your screen over AirPlay when you choose the TV in **Control Center → Screen Mirroring** (or System Settings → Displays). It also stops the session. | Verified on hardware |
| **AirPlay receiver app on the Fire TV** | Advertises an AirPlay receiver on your network, receives the stream and shows it. Fire TV has no AirPlay receiver of its own: its built-in "Display Mirroring" is Miracast, which macOS doesn't support. | Verified on hardware (AirPlay Server) |
| **ZAP** | 1. Looks for AirPlay receivers on your network (Bonjour, 2 seconds) and checks which one has the TV's address. 2. If none is there, asks the TV to open AirPlay Server through the same remote-control interface that opens other apps, then looks again (up to 10 seconds). 3. Shows the result and points you to Control Center. Pressing Mirror again while a receiver is ready opens System Settings → Displays. | Verified from code and on hardware |

ZAP **doesn't** host an AirPlay server, doesn't open any listening port, and doesn't capture or transmit your
screen. macOS doesn't let apps start Screen Mirroring by themselves, so choosing the TV is always your click.

### What is and isn't known

| Question | Answer | Evidence |
|---|---|---|
| Does ZAP need to stay open while mirroring? | No. ZAP was quit during an extended-display session and the TV kept showing the Mac; reopening ZAP picked the session up again | Verified on hardware |
| What happens if you leave the receiver on the TV (Home)? | AirPlay Server keeps running in the background and the session continues | Verified on hardware |
| How does it stop? | Stop Mirroring in Control Center → Screen Mirroring ends it, and ZAP's indicator turns off | Verified on hardware |
| Menu bar indicator (blue) and "Mirroring to TV" in the capsule | Shown while macOS uses the TV as a display | Verified on hardware when extending; mirror mode not checked separately |
| Can ZAP tell whether the receiver app is installed? | No. Sideloaded apps are missing from the app list the TV reports, so ZAP only knows a receiver exists when it is running and visible on the network | Verified on hardware |
| Mirror and extended display | Both worked with AirPlay Server (1920×1080 when extending) | Verified on hardware |
| Latency, resolution, audio | Chosen by macOS and the receiver; not measured | Not tested |
| Protected video (DRM) | Appears black when mirrored | Expected (receiver documentation) |

## The receiver ZAP is tested with: AirPlay Server

| | |
|---|---|
| App | **AirPlay Server**, shown on the network as "Android AirPlay" |
| Android package | `io.github.jqssun.airplay` |
| Developer | jqssun — [github.com/jqssun/android-airplay-server](https://github.com/jqssun/android-airplay-server) |
| License | GPL-3.0 (built on UxPlay, also GPL-3.0) |
| Distribution | F-Droid ([f-droid.org/packages/io.github.jqssun.airplay](https://f-droid.org/packages/io.github.jqssun.airplay/)), GitHub Releases and, according to its README, Google Play. **Not** in the Amazon Appstore |
| Version tested | 0.0.36 on a Fire TV Stick (3rd Gen), Fire OS 7.7.1.7. The APK we installed was byte-identical (same SHA-256) to the developer's GitHub release |
| Requirements | Android 7.0 or later according to its README (Fire OS 6, 7 and 8 meet this); 32-bit and 64-bit ARM builds |
| Ads and tracking | F-Droid lists no anti-features, and its build file declares no advertising or analytics libraries |

ZAP is not affiliated with AirPlay Server and **does not bundle, host or redistribute it**. You install it
yourself, from its developer's channels. Other AirPlay receiver apps may work if they are already running
on the TV, but they are not tested with ZAP, and ZAP never opens them.

AirPlay receiver apps for Fire TV are third-party apps, not made or certified by Apple.

## Installing the receiver on a Fire TV

Apps from outside the Amazon Appstore have to be installed ("sideloaded") with an app such as Downloader.
Fire TV warns about this, and Amazon may block some sideloaded apps. Only install apps from sources you trust.

1. On the TV, install **Downloader** (by AFTVnews) from the Amazon Appstore.
2. Allow Downloader to install apps:
   - **Fire OS 7 and 8:** Settings → My Fire TV → Developer Options → **Install unknown apps** → Downloader → On.
     If Developer Options is missing, open Settings → My Fire TV → About and select the device name seven times.
   - **Fire OS 6:** Settings → My Fire TV → Developer Options → **Apps from Unknown Sources** → On.
3. In Downloader, open `https://f-droid.org/packages/io.github.jqssun.airplay/` and download the
   suggested version's APK, then choose **Install**.
4. Open **AirPlay Server** once. It should show that its server is running.
5. Optional, recommended: turn **Install unknown apps** off again for Downloader.

How it was done in our test: the APK was downloaded from F-Droid on the Mac, its SHA-256 was compared with
the developer's GitHub release, and the TV fetched that copy from the Mac over the local network with
Downloader. The steps above use the same file from F-Droid directly; that exact path wasn't tested.

## Using it

1. Press **Mirror** in the ZAP remote. ZAP opens the receiver on the TV and tells you when your Mac can see it.
2. Open **Control Center → Screen Mirroring** and choose the receiver ("Android AirPlay"). macOS lets you
   mirror or extend your display.
3. To stop, choose **Stop Mirroring** in Control Center → Screen Mirroring.

## Things to know about the receiver

- **It is a server on your network.** While it runs, other devices on the same network can see it and try to
  connect. AirPlay Server's README lists optional PIN authentication; no PIN was asked in our test.
- **Permissions.** According to its F-Droid listing, it asks to start at boot, to draw over other apps and to run in the foreground. That's
  normal for a receiver, but worth knowing.
- **Updates.** Sideloaded apps aren't updated by the Appstore. Check F-Droid or GitHub for new versions.
- **One receiver at a time.** If AirPlay Server says "error starting server", another receiver app (for
  example AirScreen) is holding the AirPlay port. Close or uninstall it.
- **Sleep.** Fire TV may go to sleep during long sessions; the receiver's project has discussed this.

## Compatibility

Mirroring needs a Fire TV that can install Android apps from outside the Appstore. That rules out Fire TV
devices running **Vega OS** (for example the Fire TV Stick 4K Select), which only install apps from the
Appstore, and Fire OS 5 devices, which are older than the receiver supports. See
[COMPATIBILITY.md](../COMPATIBILITY.md).
