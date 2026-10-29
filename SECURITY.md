# Security

## Reporting a vulnerability

Please report security issues privately through GitHub's
[private vulnerability reporting](https://github.com/skiliz/zap/security/advisories/new) for this
repository rather than in a public issue. We aim to acknowledge reports within a week. There is no bug
bounty.

## How ZAP protects the connection to your TV

- **Pairing is authorised on the TV.** ZAP gets access only after you type the PIN the Fire TV displays.
- **TLS is always verified.** The Fire TV's remote service presents a certificate chain issued by an
  Amazon "Turnstile Server" root. At pairing, ZAP accepts that root only if its SHA-256 matches the known
  Amazon root (a host merely using the same name is refused), pins it, and from then on requires the whole
  chain to verify to it — before any request, token or audio is sent, on the command port and on the voice
  port. (The TV re-issues its leaf certificate, so pinning the leaf alone would break.) Verification is
  never disabled, and redirects are never followed.
- **The TV is never trusted by address alone.** If the TV moves to a new IP address, ZAP looks for the
  same advertised device ID, then requires the pinned TLS chain, a token the TV accepts, and the same
  serial number before sending any command. The new address is saved only after that check; a missing or
  different serial is refused.
- **Credentials** are stored in `~/Library/Application Support/ZAP Remote/device.json`, written with mode
  0600 from the start, in a folder kept at 0700. Moving the token to the Keychain is planned for the first
  Developer ID-signed release (ad-hoc builds would make macOS ask for Keychain access after every update).
- **Data from the TV is validated.** App IDs must be package names before they are used anywhere; app icons
  are downloaded only from Amazon's image hosts, capped at 2 MB, and decoded only as PNG or JPEG
  thumbnails.
- **Keyboard shortcuts** act only on keys typed into ZAP's open panel. The optional global push-to-talk
  shortcut uses the system hot-key API and needs no Accessibility or Input Monitoring permission.
- **No listening sockets.** ZAP is a client only; it opens no ports.

## Known limitations

- **Release signing:** ZAP binaries are published only when they are signed with a Developer ID and
  notarized by Apple ([docs/RELEASING.md](docs/RELEASING.md)). Until the first such release, build ZAP from
  source.
- **The TV's voice socket** (port 9090) reportedly accepts connections without authentication (as
  documented by other open-source projects). That is a property of the Fire TV, not of ZAP: anyone on
  the same local network could send audio to its Alexa channel. Use ZAP on networks you trust.
- The Fire TV interface is undocumented by Amazon and may change with Fire OS updates.

## Developer builds

`ZAP_DEVTOOLS=1 scripts/build.sh` builds a developer version with an offline UI preview, a menu bar demo and
a `zapremote://` automation interface for testing. Released apps contain none of these: the scheme is not
registered, the code isn't compiled in, and `scripts/package.sh` refuses to package a developer build.
