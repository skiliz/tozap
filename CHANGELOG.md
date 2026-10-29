# Changelog

All notable changes to ZAP are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] - Unreleased

First public release.

### Features
- **The remote:** a menu bar remote for compatible Fire TV devices in a dark graphite design.
  - Rewind / Play-Pause / Fast-forward, a circular D-pad with OK, and Back / Home / Menu.
  - Hold a direction to repeat it.
  - Keyboard control while the remote is open, including Full Keyboard Access.
- **The status capsule:** at the top of the remote it shows the TV's name and its connection, which is green
  only when recently confirmed. It briefly confirms what just happened: an app opened, a reconnection, an
  AirPlay receiver being set up or ready, the microphone starting or recognising, or what you said. It also
  shows when your screen is mirrored to the TV.
- **The menu bar icon:** a slim remote with a status light.
  - Green when the TV confirmed the connection in the last 10 minutes.
  - An amber ring while reconnecting, and a red dot with the remote dimmed when unreachable.
  - Gray when not checked; red while the microphone records; blue while the screen is shown on the TV.
  - A brief pulse when the TV accepts a command.
  - A tooltip and VoiceOver describe the state.
- **App shortcuts:** up to four, chosen from the apps installed on your TV. Reorder them by drag and drop or
  with ⌥↑ / ⌥↓, hide them without removing them, or replace them.
- **Pairing:** finds Fire TVs on the local network and pairs with the PIN shown on the TV. It finds the TV
  again after an address change, and reports when Local Network access is off.
- **Voice:** push-to-talk with Italian commands recognised on the Mac (Apple Speech), or relayed to Alexa
  through the Fire TV. An optional global ⌃⌥V shortcut, with a warning if another app already uses it.
- **Screen Mirroring helper:** opens an AirPlay receiver app on the TV and guides macOS Screen Mirroring.
- **A Settings window** with General, Device, Apps, Voice, Mirroring, Advanced and About.
  - Launch at login uses macOS login items.
  - The menu bar icon can be hidden: open ZAP again to reach Settings.
  - Copy Summary copies a diagnostic summary with no personal data.
  - Legal notices are available in About.

### Security and privacy
- **TLS to the TV:** always verified against the Amazon root pinned at pairing. Pairing accepts only the
  known Amazon root, matched by its SHA-256, and redirects are never followed.
- **After an address change:** the TV must prove the same serial before a new address is saved or a command
  is sent.
- **Data from the TV is validated:** app IDs are checked, app icons are capped at 2 MB, and only PNG/JPEG
  thumbnails are decoded.
- **Local data:** pairing data lives in `~/Library/Application Support/ZAP Remote`, written with mode 0600
  from the start. Data from pre-release builds is moved once from the folder the ZAP web security scanner
  also uses.
- **Forget This TV:** removes the pairing, app list, icons and remembered receiver, including older copies.
- **App icons:** downloaded with no cookies, cache or redirects. Logs keep app names, receiver names and
  speech private.
- **Developer tools:** the offline preview, the menu bar demo and automation are compiled only into
  developer builds (`ZAP_DEVTOOLS=1`), never into releases.

### Known limitations
- Apple silicon only; macOS 14 or later.
- Verified on one device: Fire TV Stick (3rd Gen) with Fire OS 7.7.1.7.
- No Now Playing: Fire TV doesn't expose titles, artwork or playback state to remote apps
  ([docs/NOW_PLAYING.md](docs/NOW_PLAYING.md)).
- No volume or power control. Screen Mirroring needs a third-party AirPlay receiver app on the TV.
