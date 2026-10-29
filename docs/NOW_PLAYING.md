# Now Playing on Fire TV — investigation

**Result: full Now Playing metadata is not supported by any interface verified for this device.**
ZAP therefore never shows a title, episode, artwork, progress or playback state. The status capsule shows
the TV's name and connection, and briefly confirms what ZAP itself did (for example "Netflix opened").

Investigated on 29 October 2026 with a Fire TV Stick (3rd Gen) on Fire OS 7.7.1.7, paired with ZAP, while
Netflix played an episode of a series. Only read-only requests were used: no ADB, no TV-side apps, no
changes to the TV's settings, no accounts or cloud services, and nothing that touches DRM-protected content.

## What was checked

| Source | How | What it exposes |
|---|---|---|
| Fire TV app protocol (`:8080`, the interface ZAP uses) | `GET /v1/FireTV/status`, `/v1/FireTV/properties`, `/v1/FireTV/keyboard`, with the paired token, without waking the remote service | Device data only: OS build string, platform, device type and category, marketplace, capability flags, on-screen keyboard state. No playback fields. |
| Same protocol, documented by other projects | The open-source projects credited in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) | Command-only. One project states that "the REST API cannot query current state". `/v1/media` accepts `play` and `scan` commands and returns no status. |
| DIAL (`:8009`, `GET /apps/<name>`) | Netflix, YouTube, AmazonInstantVideo, PrimeVideo, Spotify, Crunchyroll | **Netflix** answers: `stopped` before it was opened, `running` while it played. Its `additionalData` is empty. YouTube refuses the request (HTTP 403). The other names are not registered (HTTP 404). |
| Changes during playback | 60 snapshots, one every 3 seconds, while the episode was paused and resumed from ZAP | Nothing changed: Netflix stayed `running`, every other field stayed identical. |
| `GET /v1/FireTV/appsV2` | Installed-app list | App names and icons — not the app in the foreground, and not content artwork. |

## Results

| Wanted | Available? | Notes |
|---|---|---|
| Foreground application | **No** | DIAL `running` only means Netflix is running; it does not show that Netflix is on screen or playing. Other apps don't report anything. |
| Title | **No** | No interface returns it. |
| Episode / season | **No** | — |
| Playback state (playing / paused / stopped) | **No** | No field changed between playing and paused. |
| Progress / duration | **No** | — |
| Artwork | **No** | Only app icons from the installed-app list. |

## Approaches that were not used

| Approach | Possible in theory | Accessible on this device | Verified with a real app | Suitable for public distribution |
|---|---|---|---|---|
| Fire TV app protocol (`:8080`) | No (command-only) | Yes | Yes — no media data | — |
| DIAL application status | Partly (app running/stopped for apps that register) | Netflix only | Yes — `running`, no title | Not as "Now Playing": it can't tell foreground or playback |
| Android MediaSession via ADB (`dumpsys media_session`) | Yes | Only after enabling ADB debugging on the TV | Not tested | No: it needs developer settings on the TV, and many streaming apps limit what they publish |
| A companion app on the TV with notification or media-session access | Yes | Only after sideloading an app and granting it special access | Not tested | No: it needs a TV-side install and privileged access, outside an ordinary remote |
| Netflix's own second-screen protocol or cloud APIs | — | — | Not tested | No: account-bound and undocumented |
| Screen capture or recognition of the TV picture | — | — | Not tested | No: intrusive, and DRM-protected content |

## Where the investigation stopped, and why

The remote protocol is command-only, DIAL can't tell foreground or playback state, and the remaining sources
need either privileged access on the TV or account-bound services. Going further would mean changing the
TV's security settings or reverse-engineering third-party apps, which ZAP doesn't do.

## What ZAP keeps

- A typed model with provenance: `Sources/ZAPKit/NowPlaying.swift`. `NowPlayingPolicy.verifiedSources` is empty,
  so nothing is shown. A source is added only after it has been verified on a real device.
- The capsule falls back to the TV's name and never keeps the last-opened app on screen as if it were still active.

## Conclusion

This is a limitation of the platform, not a fault in ZAP's remote control. Every command (D-pad, OK, Back,
Home, Menu, Play/Pause, app launch) works on the verified device; Fire TV simply doesn't offer remote apps a
legitimate, supported way to read what is playing. Whether Netflix's DIAL state stays `running` after Home was
not tested further: it wouldn't change the result, because DIAL never reports a title or playback state. If
Amazon documents a media-status interface in the future, it can be verified and added through
`NowPlayingPolicy.verifiedSources` without changing the rest of the app.
