# Security

## Reporting a vulnerability

Please report security issues privately through GitHub's
[private vulnerability reporting](https://github.com/skiliz/tozap/security/advisories/new) for this
repository rather than in a public issue. We aim to acknowledge reports within a week. There is no bug
bounty.

## How the connection to your TV is protected

- **Pairing is authorised on the TV.** to.zap gets access only after you type the PIN the Fire TV displays.
- **TLS is always verified.** The Fire TV's remote service presents a certificate chain issued by an
  Amazon "Turnstile Server" root. At pairing, to.zap accepts that root only if its SHA-256 matches the known
  Amazon root (a host merely using the same name is refused), pins it, and from then on requires the whole
  chain to verify to it — before any request, token or audio is sent, on the command port and on the voice
  port. (The TV re-issues its leaf certificate, so pinning the leaf alone would break.) Verification is
  never disabled, and redirects are never followed.
- **The TV is never trusted by address alone.** If the TV moves to a new IP address, to.zap looks for the
  same advertised device ID, then requires the pinned TLS chain, a token the TV accepts, and the same
  serial number before sending any remote-control command. Reading the serial is itself an authenticated
  request over the pinned chain. The new address is saved only after that check; a missing or different
  serial is refused. A voice session also requires the pinned chain and an accepted token. Every Fire TV
  presents the same Amazon root, so the pin proves "a Fire TV", and the serial check is what proves "your
  Fire TV".
- **Credentials** are stored in `~/Library/Application Support/to.zap/device.json`, written with mode
  0600 from the start, in a folder kept at 0700. Any process running as your user can read it, as with other
  per-user files. Moving the token to the Keychain is planned once releases carry a stable Developer ID
  signature: with ad-hoc signed builds, macOS would ask for Keychain access again after every update.
- **Data from the TV is validated.** App IDs must be package names before they are used anywhere; app icons
  are downloaded only from Amazon's image hosts, capped at 2 MB, and decoded only as PNG or JPEG
  thumbnails.
- **Keyboard shortcuts** act only on keys typed into to.zap's open panel. The optional global push-to-talk
  shortcut uses the system hot-key API and needs no Accessibility or Input Monitoring permission.
- **No listening sockets.** to.zap is a client only; it opens no ports.
- **Update check on request only.** Check for Updates sends one HTTPS request to GitHub's public API when you
  click it, follows redirects only within `api.github.com`, refuses answers over 1 MB, and opens a release page
  only if it is on `github.com/skiliz/tozap/releases`. It never downloads, installs or runs anything, and never
  offers prereleases.

## Known limitations

- **Release signing:** release 1.0 is ad-hoc signed, **not** signed with an Apple Developer ID and **not**
  notarized by Apple. macOS can't confirm who built it, so you approve it once in System Settings → Privacy &
  Security. Check the download against `SHA256SUMS.txt` in the release, or build from source
  ([docs/RELEASING.md](docs/RELEASING.md)).
- **The mirroring receiver is third-party software.** to.zap doesn't ship or install it. While it runs on the TV
  it is an AirPlay server reachable by other devices on your network ([docs/MIRRORING.md](docs/MIRRORING.md)).
- **The TV's voice socket** (port 9090) reportedly accepts connections without authentication (as
  documented by other open-source projects). That is a property of the Fire TV, not of to.zap: anyone on
  the same local network could send audio to its Alexa channel. Use to.zap on networks you trust.
- The Fire TV interface is undocumented by Amazon and may change with Fire OS updates.

## Developer builds

`ZAP_DEVTOOLS=1 scripts/build.sh` builds a developer version with an offline UI preview, a menu bar demo and
a `zapremote://` automation interface for testing. Released apps contain none of these: the scheme is not
registered, the code isn't compiled in, and `scripts/package.sh` refuses to package a developer build.
