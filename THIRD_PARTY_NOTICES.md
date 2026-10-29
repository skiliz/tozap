# Third-party notices

## Code and dependencies

ZAP contains **no third-party code** and has **no package dependencies**. It is written in Swift against
Apple's system frameworks (SwiftUI, AppKit, Foundation, Network, Security, CryptoKit, ImageIO, AVFoundation,
Speech, ServiceManagement, Carbon; ScreenCaptureKit in developer builds only), which are part of macOS and are
not redistributed.

## Graphics

- The ZAP icon, menu bar glyph and wordmark are original and generated from
  [`branding/make-assets.swift`](branding/make-assets.swift) (sources in `branding/*.svg`). They are covered
  by this repository's MIT license.
- Inside the app's own controls ZAP uses Apple's built-in **SF Symbols** (e.g. arrows, house, mic) through
  the system API, as Apple permits for app interfaces on Apple platforms. SF Symbols are not used in the
  app icon or the ZAP marks, and they are not redistributed as files.
- Fonts: the app uses the system font; no font files are included.
- **App icons** shown on shortcut tiles are not part of ZAP: they are the icons your Fire TV lists for
  its installed apps, downloaded at run time from Amazon's image servers and cached only on your Mac
  (on by default; Settings → Advanced turns it off). They belong to their respective owners, and screenshots that show
  them do not imply any affiliation.

## Protocol knowledge

ZAP talks to the Fire TV through the local network interface that the official Fire TV mobile app uses.
How that interface works was learned from public open-source projects and by observing the responses of
a Fire TV owned by the developers — no Amazon software was decompiled and no Amazon code, keys, firmware,
APKs or assets are included. These projects documented the interface and are credited with thanks;
**none of their code is included in ZAP**:

- [LibreControl/fire-tv](https://github.com/LibreControl/fire-tv)
- [hms-homelab/hms-firetv](https://github.com/hms-homelab/hms-firetv)
- [mase1981/uc-intg-firetv](https://github.com/mase1981/uc-intg-firetv)
- The Home Assistant community thread "REST commands for Fire TV"

The request header value `0987654321` used by the interface is a fixed, publicly documented identifier
of the Fire TV app protocol (not a secret or a credential); each user's access is authorised by the PIN
pairing shown on their own TV.

## Optional software ZAP works with

ZAP does not bundle or distribute any of these:

- **AirPlay receiver apps for Fire TV**, needed only for Screen Mirroring. ZAP is tested with
  [AirPlay Server](https://github.com/jqssun/android-airplay-server) by jqssun (GPL-3.0, free; package
  `io.github.jqssun.airplay`), which ZAP can open on the TV by its package name. No part of it, or of UxPlay
  on which it is built, is included in ZAP. Receivers are installed by the user, on the TV, from their
  developers' channels and under their own licences.
- **Alexa** (Amazon) processes voice when you choose the Alexa voice mode.

## Trademarks

Amazon, Fire TV, Fire OS and Alexa are trademarks of Amazon.com, Inc. or its affiliates. Apple, Mac, macOS,
AirPlay and SF Symbols are trademarks of Apple Inc., registered in the U.S. and other countries and regions.
Other product names are trademarks of their respective owners. They are used only to describe compatibility.
ZAP is an independent project and is not affiliated with, endorsed by, or sponsored by Amazon or Apple.
AirPlay receiver apps for Fire TV are third-party apps, not made or certified by Apple. ZAP is unrelated to
the ZAP web security scanner (ZAP by Checkmarx, formerly OWASP ZAP).
