# Changelog

All notable changes to to.zap are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-29

First public release.

### Features
- **The remote:** a menu bar remote for compatible Fire TV devices in a dark graphite design.
  - Rewind / Play-Pause / Fast-forward, a circular D-pad with OK, and Back / Home / Menu.
  - Hold a direction to repeat it.
  - Keyboard control while the remote is open, including Full Keyboard Access.
- **The status capsule:** at the top of the remote it shows the TV's name and its connection, which is green
  only when recently confirmed. It briefly confirms what just happened: an app opened, a reconnection, an
  AirPlay receiver being set up or ready, the microphone starting or recognising, or what you said. It also
  shows when macOS uses the TV as a display (verified when extending the desktop).
- **The menu bar icon:** a slim remote with a status light.
  - Green when the TV confirmed the connection in the last 10 minutes.
  - An amber ring while reconnecting, and a red dot with the remote dimmed when unreachable.
  - Gray when not checked; red while the microphone records; blue while macOS uses the TV as a display.
  - A brief pulse when the TV accepts a command.
  - A tooltip and VoiceOver describe the state.
- **App shortcuts:** up to four, chosen from the apps installed on your TV. Reorder them by drag and drop or
  with ⌥↑ / ⌥↓, hide them without removing them, or replace them.
- **Pairing:** finds Fire TVs on the local network and pairs with the PIN shown on the TV. It finds the TV
  again after an address change, and reports when Local Network access is off.
- **Voice:** push-to-talk with Italian commands recognised on the Mac (Apple Speech), or relayed to Alexa
  through the Fire TV. An optional global ⌃⌥V shortcut, with a warning if another app already uses it.
- **Screen Mirroring helper:** opens the AirPlay Server receiver app on the TV, checks that the Mac can see it,
  and guides macOS Screen Mirroring. to.zap doesn't stream video; mirroring continues if to.zap quits.
- **Check for Updates** in Settings → About: one request to GitHub's public API when clicked, never in the
  background. It compares versions by Semantic Versioning, never offers prereleases, and points Homebrew
  installs to `brew upgrade`.
- **A Settings window** with General, Device, Apps, Voice, Advanced and About.
  - Launch at login uses macOS login items.
  - The menu bar icon can be hidden: open to.zap again to reach Settings.
  - Copy Summary copies a diagnostic summary with no personal data.
  - About shows the app's identity, version, the GitHub repository and Check for Updates. The license and
    third-party notices ship inside the app bundle and in the repository.

### Security and privacy
- **TLS to the TV:** always verified against the Amazon root pinned at pairing. Pairing accepts only the
  known Amazon root, matched by its SHA-256, and redirects are never followed.
- **After an address change:** the TV must prove the same serial before a new address is saved or a command
  is sent.
- **Data from the TV is validated:** app IDs are checked, app icons are capped at 2 MB, and only PNG/JPEG
  thumbnails are decoded.
- **Local data:** pairing data lives in `~/Library/Application Support/to.zap`, written with mode 0600
  from the start. Pairing data and settings from pre-release builds (named "ZAP") are moved there once.
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
- No previous/next episode, track or channel: Fire TV's remote interface has no such command (tested), so the
  side buttons are Rewind and Fast-forward, which send the interface's seek command.
- No volume or power control. Screen Mirroring needs a third-party AirPlay receiver app sideloaded on the TV,
  which isn't possible on Vega OS devices.
- Not signed with an Apple Developer ID and not notarized: macOS asks you to approve the app once, and again
  after each update.
