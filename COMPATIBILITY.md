# Compatibility

## Mac

| | |
|---|---|
| macOS | 14 Sonoma or later (minimum required by the APIs ZAP uses). **Tested on macOS 27.0.1.** |
| Processor | **Apple silicon only** in 1.0. An Intel build could not be verified, so none is shipped. |
| Signing | Downloads are published only signed with a Developer ID and notarized by Apple. Until the first such release, build from source. |

## Fire TV

Only the device below has been tested. Other Fire TV models running Fire OS 7 or 8 use the same local
interface according to other open-source projects, but **they are unverified with ZAP**.

| Device | Fire OS | Result |
|---|---|---|
| Fire TV Stick (3rd Gen, 2020) — model AFTSSS | 7.7.1.7 | Verified, see below |

### Feature status on the verified device

| Feature | Status |
|---|---|
| PIN pairing, wake from idle, reconnect | Verified |
| D-pad, OK, Back, Menu, Home; hold to repeat | Verified |
| Launching installed apps (Netflix and others) | Verified |
| Play/Pause, Rewind, Fast-forward | Play/Pause verified in Netflix (pause and resume). The effect depends on the app in front: in one IPTV app the same commands changed channel |
| Connection status (capsule and menu bar light) | Verified (green when connected) |
| Now Playing (title, episode, artwork, playback state) | **Not available**: Fire TV doesn't expose it to remote apps — see [docs/NOW_PLAYING.md](docs/NOW_PLAYING.md) |
| Voice — Apple Speech, Italian, on-device | Verified |
| Voice — relay to Alexa | Verified (Alexa answered) |
| Screen Mirroring helper (opens the receiver app, guides macOS Screen Mirroring) | Verified with the AirPlay Server receiver; mirror and extended display both worked |
| Volume, mute, power | **Not available**: the TV accepts the volume requests but treats them as arrow keys; TV volume is normally changed by the remote over IR/HDMI-CEC |
| Channel up/down inside IPTV apps | Not supported (not verified) |
| Typing text into apps | Not supported (the TV dropped text sent this way) |

## Network

- The Mac and the Fire TV must be on the **same local network** and able to reach each other.
- Phone hotspots often isolate their clients; on an iPhone Personal Hotspot the Mac could not reach the
  TV at all. A home router — or macOS Internet Sharing with the TV joined to the Mac — works.
- Bonjour (mDNS) must be allowed between devices for automatic discovery; you can also enter the TV's
  address manually when pairing.
- macOS asks once for **Local Network** access; if it's denied, ZAP says so and points to System Settings →
  Privacy & Security → Local Network.

## Screen Mirroring

Fire TV Sticks have no built-in AirPlay; their own "Display Mirroring" is Miracast, which macOS does not
support. You need an AirPlay receiver app on the TV:

| Receiver | Cost | Notes |
|---|---|---|
| [AirPlay Server](https://github.com/jqssun/android-airplay-server) | Free, open source (GPL-3.0) | Worked with ZAP. Not in Amazon's Appstore: it's distributed through F-Droid and GitHub, and installing apps from outside the Appstore requires allowing *Install unknown apps* for the app you install it with. Shows up as "Android AirPlay". |
| AirScreen | Free with ads; Mac mirroring needed the paid tier in our test | In the Amazon Appstore. Don't run it together with another receiver (they compete for the AirPlay ports). |

Protected video (DRM) shows black when mirrored. Latency and audio quality depend on the receiver and
the network and were not measured.

AirPlay receiver apps for Fire TV are third-party apps, not made or certified by Apple.
