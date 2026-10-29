# How ZAP talks to a Fire TV

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
pairing, `x-client-token`. TLS: see [SECURITY.md](../SECURITY.md) — ZAP pins the Amazon root chain.

## Now Playing (not available)

The live investigation on a real device is in [NOW_PLAYING.md](NOW_PLAYING.md); in short:

ZAP models playback metadata with its provenance (`Sources/ZAPKit/NowPlaying.swift`) and shows a title in
the status capsule only when it comes from a source verified on a real device. **No source is verified
yet**, so ZAP never shows a title, artwork or progress today. What is known, from the read-only calls ZAP
already makes:

| Source | What it can tell | Status |
|---|---|---|
| `GET /v1/FireTV/status` | `osVersion`, `platformType`, `turnstileVersion` — no playback fields | observed |
| `GET /v1/FireTV/properties` | device properties (`dsn`, `osVersion`, capability flags) — no playback fields | observed |
| `GET /v1/FireTV/keyboard` | on-screen keyboard state only | observed |
| DIAL `GET http://<tv>:8009/apps/<name>` | at most "running"/"stopped" for apps registered with DIAL; never a title | needs a live test |
| Android media sessions | would need ADB debugging on the TV, which ZAP does not ask users to enable | out of scope |

Streaming apps decide what they publish: Netflix and other DRM services may expose no title at all even
where a media session exists. Any new source must be confirmed on a real TV (with the owner's approval)
before it is added to `NowPlayingPolicy.verifiedSources`.
