# Privacy

to.zap is local-first. It has no account, no Cosmos server, no analytics, no telemetry, no crash reporting and
no automatic update check. It opens no listening ports. to.zap talks to:

- **your Fire TV**, on your local network;
- **Amazon's image servers**, by default, for the icons of the apps on your TV (you can turn this off);
- **Amazon's Alexa service**, through your Fire TV, only in Alexa voice mode and only while you hold
  push-to-talk;
- **Apple's speech servers**, only if your Mac can't recognise Italian on-device *and* you turn on
  *Allow Apple server recognition* (off by default);
- **GitHub**, only when you click *Check for Updates* in Settings → About.

## What stays on your Mac

| Data | Where | Why |
|---|---|---|
| Pairing: the TV's local address, the access token from PIN pairing, the pinned Amazon TLS root certificate, the TV's advertised name and ID, its serial number and Fire OS build, an optional nickname, the pairing date | `~/Library/Application Support/to.zap/device.json` (mode 0600, folder 0700) | to control the paired TV and recognise it again |
| The TV's list of installed apps | `~/Library/Application Support/to.zap/apps.json` (0600) | app shortcuts |
| App icons | `~/Library/Application Support/to.zap/icons-v2/` | shortcut tiles |
| The name of the TV's own AirPlay receiver, after you use Mirror | to.zap's preferences | the menu bar's mirroring light |
| Settings: shortcuts, voice mode, consent to Apple server recognition, push-to-talk, menu bar and display options, connection checks, the Settings window position | `~/Library/Preferences/local.tozap.app.plist` | preferences |

None of this is sent anywhere. **Settings → Device → Forget This TV** deletes the pairing, the app list, the
downloaded icons and the remembered receiver name, including the copy left by pre-1.0 "Fire Remote"
builds. Your shortcuts and other preferences stay. To remove everything, see *Uninstall* in the README.

## App icons

With **Settings → Advanced → Show app icons** on (the default), to.zap downloads the icon your TV lists for each
installed app. It does this when it reads the TV's app list, and at launch for icons it hasn't saved yet.
The icons come from Amazon's image servers (`m.media-amazon.com`, `images-na.ssl-images-amazon.com`); other
hosts and redirects are refused. These requests show Amazon your public IP address, the time, and which
apps are on your TV. to.zap sends no cookies and keeps no HTTP cache; the requests carry only standard HTTP headers, with the user agent `to.zap`.

Turn the option off to keep to.zap's own traffic on your local network, apart from Alexa mode and optional
Apple server recognition. Neutral symbols are shown instead, and **Remove** deletes the saved icons.

## Check for Updates

to.zap never checks for updates by itself. When you click **Settings → About → Check for Updates**, it sends one
HTTPS request to GitHub's public API (`api.github.com/repos/skiliz/tozap/releases/latest`) to read the latest
release's version. The request carries no account, token or cookie, only standard HTTP headers (such as your
preferred language) with the user agent `to.zap`, and nothing is cached. GitHub sees your IP address and the time, under GitHub's privacy statement.
Nothing is downloaded or installed: if a newer version exists, to.zap shows it and opens the release page in your
browser only if you ask. To check whether to.zap was installed with Homebrew, to.zap looks for Homebrew's
`Caskroom/tozap-remote` folder on your Mac; nothing about it is sent anywhere.

**GitHub Repository** simply opens to.zap's page on github.com in your browser.

## Microphone

- The microphone is used **only while you hold push-to-talk** (the Voice button, V in the panel, or the
  optional ⌃⌥V shortcut), or, if you activate the Voice button with Full Keyboard Access or VoiceOver, until
  you activate it again. It stops when you release it, when the panel closes, when the audio device
  changes, when the connection fails, and in any case after 15 seconds.
- macOS shows its microphone indicator while to.zap listens, and asks for your permission the first time.
- **No audio is recorded or stored** by to.zap.

### Apple Speech mode (default)

Apple's Speech framework recognises your speech **on your Mac**, and to.zap requires on-device recognition
whenever your Mac supports it for Italian. If it doesn't, nothing is sent to Apple unless you turn on
*Allow Apple server recognition* in Settings → Voice; that option is then subject to Apple's privacy policy.
Recognised text is shown in the panel and is not saved.

### Alexa mode (optional)

While you hold push-to-talk, to.zap streams your voice (16 kHz audio) to your **Fire TV**, which sends it to
**Amazon's Alexa service in the cloud**, as the voice button on the Fire TV remote does. Amazon's privacy
terms apply to that audio. Settings calls this mode "Alexa on the Fire TV (Amazon cloud)", and the Voice
button's tooltip says "Sent to Alexa through the Fire TV (Amazon cloud)".

## Local network

to.zap asks macOS for Local Network access in order to:

- find Fire TVs (Bonjour);
- check whether the paired TV is reachable (a read-only DIAL request when the remote opens, which
  Settings → Advanced can turn off, and again after a command fails). If the TV doesn't answer, to.zap looks
  for it on the network with Bonjour, in case it got a new address;
- send your commands to the TV's remote-control service;
- find the TV's AirPlay receiver for Screen Mirroring: to.zap briefly connects to each AirPlay receiver it
  sees to read its address, and remembers only the name of the one on your TV.

## Logs and diagnostics

to.zap writes diagnostic messages, mostly timings and errors, to the macOS unified log (Console). It marks
command and app names, request paths, AirPlay receiver names and recognised speech as private, so macOS
redacts them. **Settings → Advanced → Copy Summary** puts on your clipboard, and nowhere else:

- the to.zap and macOS versions;
- the connection state;
- your voice, icon, shortcut, login-item and menu bar settings.

It contains no names, addresses or tokens.

## Screen Mirroring

to.zap does not capture or transmit your screen. macOS performs Screen Mirroring (Control Center), together with
the AirPlay receiver app you install on the TV. That receiver is third-party software with its own behaviour:
while it runs, it is an AirPlay server visible to other devices on your network. See
[docs/MIRRORING.md](docs/MIRRORING.md).

## Permissions

to.zap may ask for the following, each only when first needed:

- Local Network;
- Microphone, the first time you hold push-to-talk;
- Speech Recognition, in Apple Speech mode.

It registers as a login item only if you turn on *Launch at login*.
