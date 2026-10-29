# The Fire TV interface to.zap uses

Interoperability notes for contributors. This describes the local network interface used by the Fire TV
mobile app, as documented by open-source projects (see [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md))
and as observed on the verified device. Amazon does not document it and may change it.

| Purpose | Request |
|---|---|
| Discover | Bonjour `_amzn-wplay._tcp`; the TXT record carries the TV's name (`n`) and a device ID (`u`) |
| Is it reachable? (never wakes it) | `GET http://<tv>:8009/apps/FireTVRemote` (DIAL status) |
| Start the remote service | `POST http://<tv>:8009/apps/FireTVRemote` (DIAL). It stops again when idle. May turn the TV on via HDMI-CEC. |
| Show a PIN | `POST https://<tv>:8080/v1/FireTV/pin/display` `{"friendlyName": "…"}` |
| Pair | `POST https://<tv>:8080/v1/FireTV/pin/verify` `{"pin": "1234"}` → token in `description` |
| Keys | `POST /v1/FireTV?action=<dpad_up…select, home, back, menu>`; no body = one press, `{"keyActionType":"keyDown"/"keyUp"}` = hold |
| Media | `POST /v1/media?action=play` (toggle); `action=scan` with `{"direction":"forward"/"back", "keyAction":{…}}` |
| Apps | `GET /v1/FireTV/appsV2`; launch with `POST /v1/FireTV/app/<package>` |
| Identity | `GET /v1/FireTV/properties` (authenticated) |
| Voice to Alexa | `POST /v1/FireTV/voiceCommand?action=start`, then `wss://<tv>:9090/` with 16 kHz mono 16-bit PCM in binary frames, close to finish, `action=stop` |

All `:8080` and `:9090` requests carry `x-api-key` (a fixed public value of the protocol) and, after
pairing, `x-client-token`. TLS: see [SECURITY.md](../SECURITY.md) — to.zap pins the Amazon root chain.

## Previous / next (not available)

There is no previous/next command (episode, track or channel) in this interface. Tested on 29 October 2026 on
the verified Fire TV Stick (Fire OS 7.7.1.7), with the owner watching the TV:

- **Negative control:** made-up actions (`/v1/FireTV?action=zap_bogus`, `/v1/media?action=zap_bogus`) are
  refused with HTTP 400 "Bad arguments supplied", so the TV does validate action names.
- **Refused the same way (400):** `/v1/media?action=` `next`, `previous`, `skip_next`, `skip_previous`,
  `skipNext`, `skipPrevious`, `next_track`, `previous_track`; `/v1/FireTV?action=` `media_next`,
  `media_previous`, `next`, `previous`, `channel_up`, `channel_down`, `media_next_track`,
  `media_previous_track`, `skip_forward`, `skip_backward`; `scan` with `direction` `next`, `previous` or `skip`.
- **Accepted (200):** `scan` with `direction` `forward` — a seek, not a skip.

The other open-source implementations also have no such command; where they show "next", it sends `scan`.
Android's real skip keys (`KEYCODE_MEDIA_NEXT` / `KEYCODE_MEDIA_PREVIOUS`) are reachable only through ADB
debugging on the TV, which to.zap doesn't use. to.zap's side buttons therefore stay **Rewind** and
**Fast-forward**, named for what they send. What `scan` does is up to the app in front: most seek, and in one
IPTV app it changed channel.

## Now Playing (not available)

The live investigation on a real device is in [NOW_PLAYING.md](NOW_PLAYING.md); in short:

to.zap models playback metadata with its provenance (`Sources/ZAPKit/NowPlaying.swift`) and shows a title in
the status capsule only when it comes from a source verified on a real device. **No source is verified
yet**, so to.zap never shows a title, artwork or progress today. What is known, from the read-only calls to.zap
already makes:

| Source | What it can tell | Status |
|---|---|---|
| `GET /v1/FireTV/status` | `osVersion`, `platformType`, `turnstileVersion` — no playback fields | observed |
| `GET /v1/FireTV/properties` | device properties (`dsn`, `osVersion`, capability flags) — no playback fields | observed |
| `GET /v1/FireTV/keyboard` | on-screen keyboard state only | observed |
| DIAL `GET http://<tv>:8009/apps/<name>` | at most "running"/"stopped" for apps registered with DIAL; never a title | needs a live test |
| Android media sessions | would need ADB debugging on the TV, which to.zap does not ask users to enable | out of scope |

Streaming apps decide what they publish: Netflix and other DRM services may expose no title at all even
where a media session exists. Any new source must be confirmed on a real TV (with the owner's approval)
before it is added to `NowPlayingPolicy.verifiedSources`.
