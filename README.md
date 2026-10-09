# ProbeHarbor for iOS

Native SwiftUI client for [probeharbor.dev](https://probeharbor.dev). Like the
[Android app](https://github.com/doodersrage/probeharbor-android), the iPhone
doesn't sense anything itself: it signs in to your ProbeHarbor account and shows
live readings, history, and alerts from your probes.

## Features

Same screens as the Android app:

- **Sign in** with email/password, Google, GitHub, or Discord; TOTP or YubiKey OTP for two-step verification
- **Home**: live sensors, time to freeze, house reference, regional benchmark, NWS alerts, nights at risk, door sessions, heating insights, space filter (refreshes every 30 s)
- **History**: 24 h / 7 / 30 day chart with the house overlay, recent readings, claims pack (open, share, or email to an adjuster)
- **Alerts**: inbox with acknowledge, test alert, snooze / vacation, alert settings and channels
- **Devices**: rename, set space, waiting-for-first-data status, thermostat (Nest / Ecobee) status and connect links
- **Account**: display preferences, push alerts, referral link, plans; **Household**, **Share links**, and **Portfolio**
- **Push alerts** through Firebase Cloud Messaging, with an *Acknowledge* action on the notification

## Build

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # Supabase URL + anon key (same as the web .env)
xcodegen generate
open ProbeHarbor.xcodeproj
```

Without `Secrets.xcconfig`, email sign-in is disabled; Google/GitHub/Discord still work because they run through the site.

CI (`.github/workflows/ci.yml`) builds and runs the unit tests on an iOS Simulator for every push.

## Push notifications

Push is wired up but stays off until the build has:

1. An Apple Developer Program team set as `DEVELOPMENT_TEAM` in `project.yml`, with the Push Notifications capability on `dev.probeharbor.ios`.
2. An APNs key uploaded to the existing Firebase project (Project settings → Cloud Messaging → Apple app configuration).
3. An iOS app `dev.probeharbor.ios` added to that Firebase project, with its `GoogleService-Info.plist` placed at `ProbeHarbor/GoogleService-Info.plist` (gitignored).

The server already sends iOS-ready messages (APNs block with the `PROBE_ALERT` category) to tokens registered with `platform: "ios"`.

## How it talks to the server

- Session: the same `sb-access-token` / `sb-refresh-token` cookies as the web dashboard, kept in the Keychain. Rotated tokens from `Set-Cookie` replace the stored session.
- OAuth: `ASWebAuthenticationSession` opens `/api/auth/mobile/start?provider=…&app=dev.probeharbor.ios`; the site redirects to `dev.probeharbor.ios://oauth?exchange=…`, which the app trades at `/api/auth/mobile/exchange`.
- Settings writes are the dashboard's form POSTs; success is the redirect flag (`alert_saved=1`, `created=1`, …).
