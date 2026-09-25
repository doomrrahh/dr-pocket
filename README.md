<div align="center">

<img src="ios/DrPocket/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="112" alt="Dr. Pocket">

# Dr. Pocket

**A modern iPhone dashboard for your Medtronic CareLink data.**

Glucose, trend, time in range, pump battery, reservoir and active insulin —
on your phone, stored on your phone.

[![Build iOS app](https://github.com/doomrrahh/dr-pocket/actions/workflows/ios.yml/badge.svg)](https://github.com/doomrrahh/dr-pocket/actions/workflows/ios.yml)

</div>

---

> [!WARNING]
> **Dr. Pocket is not a medical device.** It is an independent, unofficial reader and is
> not made by, endorsed by or affiliated with Medtronic. Readings can be delayed, wrong or
> missing. **Never make a treatment decision from this app** — always confirm on your pump
> or meter.

## Install

Every push builds an unsigned `.ipa`. Grab the newest one from
[**Releases**](https://github.com/doomrrahh/dr-pocket/releases), or from the
[Actions tab](https://github.com/doomrrahh/dr-pocket/actions) if you want a build from a
specific commit.

You sign it yourself with a **free Apple ID** — no paid developer account, no App Store.

| You have | Use |
|---|---|
| Windows or macOS + a cable | [Sideloadly](https://sideloadly.io) — drag in the `.ipa`, enter your Apple ID |
| Windows or macOS, want auto-refresh | [AltStore](https://altstore.io) |
| Only the iPhone | [SideStore](https://sidestore.io) |

After installing, open **Settings → General → VPN & Device Management** and trust your
own certificate. A free Apple ID signature lasts **7 days**; AltStore and SideStore
refresh it over Wi-Fi so the app keeps working.

## Signing in

Tap **Sign in with CareLink**. Medtronic's real login page opens in a system web view —
you type your password and solve their captcha there. Dr. Pocket never sees either.

What comes back is an OAuth authorization code, which the app exchanges for a refresh
token stored in the iOS Keychain. After that it renews itself, so you sign in once.

This is the same flow the official CareLink Connect app uses, adapted from
[carelink-python-client](https://github.com/ondrej1024/carelink-python-client). It works
for both patient accounts and care partners (following someone else's pump).

## What it shows

- Current glucose with trend, change since the last reading, and a stale-data warning
- Glucose chart over 3, 6, 12 or 24 hours, scrubbable, with the target band drawn in
- Time in range, plus average, estimated A1c (GMI) and variability (CV)
- Pump battery, reservoir units, active insulin, sensor life, Auto Mode state
- mg/dL or mmol/L, and your own low/high thresholds

Readings are cached on the device for 14 days, so the charts survive a relaunch and still
work with no signal. Nothing is sent anywhere except to Medtronic. There is no Dr. Pocket
server and no analytics.

## Building it yourself

CI does this on every push, but locally on a Mac:

```bash
brew install xcodegen
cd ios && xcodegen generate && open DrPocket.xcodeproj
```

The Xcode project is generated from [`ios/project.yml`](ios/project.yml) and is not
checked in. Requires Xcode 16 and iOS 17 or newer.

## The desktop version

[`web/`](web) holds the original local server — plain Node, zero dependencies, a browser
dashboard and Nightscout-shaped read endpoints at `/api/v1/entries.json`.

```bash
cd web && npm start     # http://localhost:1337
```

It starts in demo mode so you can look around. Sign-in there uses the same OAuth flow:
it opens the CareLink login, then asks you to paste back the `com.medtronic.carepartner:/sso?code=…`
address your browser fails to open. See [`web/README.md`](web/README.md).

## Credits

The CareLink auth flow and endpoint map come from
[ondrej1024/carelink-python-client](https://github.com/ondrej1024/carelink-python-client)
and the login work by [@palmarci](https://github.com/palmarci).
The API shape follows [Nightscout](https://github.com/nightscout/cgm-remote-monitor).

## Licence

MIT — see [LICENSE](LICENSE).
