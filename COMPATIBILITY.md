# Compatibility

## Mac

| | |
|---|---|
| macOS | 14 Sonoma or later (the minimum the app is built for). **Tested on macOS 27.0.1.** |
| Processor | **Apple silicon only.** The app is built for arm64; an Intel build was never tested, so none is shipped. |
| Signing | Release 1.0 is **not signed with an Apple Developer ID and not notarized**. macOS asks you to approve it once; see *Install* in the README. |

## Fire TV

ZAP has two parts with different requirements:

- **Remote control** uses the local network interface of Amazon's Fire TV mobile app (discovery, PIN
  pairing, keys, app launching). It needs nothing installed on the TV.
- **The Screen Mirroring helper** needs an AirPlay receiver app that you sideload on the TV (see
  [docs/MIRRORING.md](docs/MIRRORING.md)). A TV can work as a remote target and still be unable to install
  the receiver.

Only one device has been tested with ZAP. Everything else below is what public evidence suggests, not a
promise.

**Legend:** **Tested**: tested and confirmed with ZAP · **Documented**: supported by documented evidence,
not tested with ZAP · **Unknown** · **Unsupported**

| Device (model code, year) | Operating system | Remote control | Mirroring helper |
|---|---|---|---|
| Fire TV Stick 3rd Gen (AFTSSS, 2020) | Fire OS 7.7.1.7 | **Tested** | **Tested** with AirPlay Server 0.0.36 |
| Fire TV Stick Lite (AFTSS, 2020), Stick 4K Max 1st Gen (AFTKA, 2021), Fire TV Cube 2nd/3rd Gen (AFTR, AFTGAZL), Fire OS 7 smart TVs | Fire OS 7 (Android 9) | Documented: same Fire OS 7 platform as the tested device | Documented: meets the receiver's Android version |
| Fire TV Stick 4K 2nd Gen (AFTKM, 2023), Stick 4K Max 2nd Gen (AFTKRT, 2023), Fire OS 8 smart TVs | Fire OS 8 (Android 11) | Documented: other open-source projects report pairing and control on Fire OS 8 devices | Documented |
| Fire TV Stick 4K 1st Gen (AFTMM, 2018), Fire TV Cube 1st Gen (AFTA), Fire TV 3rd Gen (AFTN), Fire OS 6 TVs | Fire OS 6 (Android 7.1) | Unknown: no project reports testing Fire OS 6 | Documented: meets the receiver's Android version |
| Fire TV Stick 1st/2nd Gen, Fire TV 1st/2nd Gen | Fire OS 5 (Android 5.1) | Unknown | **Unsupported**: older than the receiver supports |
| Fire TV devices with Fire OS based on Android 14 (2026 smart TVs) | Fire OS (Android 14) | Unknown | Unknown |
| Vega OS devices, e.g. Fire TV Stick 4K Select (AFTCA002, 2025) | Vega OS (Linux-based) | Unknown: no public evidence either way | **Unsupported**: Vega OS installs apps only from the Appstore, not Android APKs |

Amazon has said future Fire TV Sticks will run Vega OS, so newer sticks are increasingly likely to fall in the
last row. Reports from other devices are welcome: please open a compatibility report on GitHub.

### Feature status on the tested device

| Feature | Status |
|---|---|
| PIN pairing, wake from idle, reconnect | Verified |
| D-pad, OK, Back, Menu, Home; hold to repeat | Verified |
| Launching installed apps (Netflix and others) | Verified |
| Play/Pause | Verified in Netflix (pause and resume) |
| Rewind / Fast-forward | Sends the Fire TV "scan" (seek) command. What it does depends on the app in front: in one IPTV app it changed channel |
| Previous / next item (episode, track, channel) | **Not available**: the Fire TV remote interface has no previous/next command (see the README) |
| Connection status (capsule and menu bar light) | Verified |
| Now Playing (title, episode, artwork, playback state) | **Not available**: Fire TV doesn't expose it to remote apps, see [docs/NOW_PLAYING.md](docs/NOW_PLAYING.md) |
| Voice — Apple Speech, Italian, on-device | Verified |
| Voice — relay to Alexa | Verified (Alexa answered) |
| Screen Mirroring helper | Verified with AirPlay Server: mirror and extended display worked, the menu bar indicator followed the session, and mirroring continued after ZAP quit |
| Volume, mute, power | **Not available**: the TV accepts the volume requests but treats them as arrow keys |
| Typing text into apps | Not supported (the TV dropped text sent this way) |

The Fire TV interface ZAP uses isn't documented by Amazon, so a Fire OS or Fire TV app update could change it.

## Network

- The Mac and the Fire TV must be on the **same local network** and able to reach each other, with Bonjour
  (mDNS) allowed between devices. You can also enter the TV's address by hand when pairing.
- Phone hotspots and guest networks often isolate their clients; on an iPhone Personal Hotspot the Mac could
  not reach the TV at all. A home router, or macOS Internet Sharing with the TV joined to the Mac, works.
- A VPN running on the TV can break the connection.
- macOS may ask for **Local Network** access. If it's denied, ZAP says so and points to System Settings →
  Privacy & Security → Local Network.

## Screen Mirroring receivers

Fire TV has no AirPlay receiver of its own; its "Display Mirroring" is Miracast, which macOS doesn't support.

| Receiver | Cost | Notes |
|---|---|---|
| [AirPlay Server](https://github.com/jqssun/android-airplay-server) | Free, open source (GPL-3.0) | Tested with ZAP, and the only receiver ZAP opens. Distributed through F-Droid and GitHub, not the Amazon Appstore. Shows up as "Android AirPlay". |
| Other receivers (for example AirScreen in the Amazon Appstore) | Varies | Not tested with ZAP. ZAP can use one only if it is already running. Don't run two receivers at once: they compete for the AirPlay port. |

Protected video (DRM) shows black when mirrored. Latency and audio quality depend on the receiver and the
network and were not measured.

AirPlay receiver apps for Fire TV are third-party apps, not made or certified by Apple.
