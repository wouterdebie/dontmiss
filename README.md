# Don't Miss

A native macOS menu-bar app that makes meetings hard to miss. Built with SwiftUI
and AppKit, inspired by [In Your Face](https://www.inyourface.app/mac/).

## Features

- Mint-accented, frosted-glass alerts on the display containing your mouse pointer.
- Multiple Google accounts with independent calendar selection.
- Day-grouped agenda with Today and Next 7 days views and a slim, edge-aligned scrollbar.
- Clickable event details with guests, notes, meeting links, and local reminder controls.
- Configurable lead time, one-minute snooze, dismissal, and one-click meeting join.
- Offline reminders from a local cache, optional sound, and launch at login.
- Read-only Calendar access; OAuth credentials stay in macOS Keychain.
- Signed updates through Sparkle, with optional daily checks and user-approved installation.

## Install

Release builds support **Apple Silicon Macs running macOS 14+**. Download the ZIP
from [GitHub Releases](https://github.com/wouterdebie/dontmiss/releases), unzip it,
and move **Don't Miss.app** to Applications.
Use **Check for Updates** from the menu or Settings. Automatic checks are off by
default; even when enabled, installing an update requires your approval.

## Build and run

Requires **macOS 14+** and **Xcode with Swift 6+**. SwiftPM downloads the pinned
[Sparkle](https://sparkle-project.org/) dependency.

```sh
swift package resolve
swift test
bash scripts/bundle.sh
open "dist/Don't Miss.app"
```

Official signing is pinned to the current Developer ID certificate fingerprint in
`scripts/sign.sh`. Set `CODESIGN_IDENTITY` to that fingerprint when bundling;
otherwise signing is ad-hoc. For local notarization, run
`NOTARY_PROFILE="<Keychain profile>" bash scripts/notarize.sh`.

## Releases

Push a `vMAJOR.MINOR.PATCH` tag on a commit from `main`. GitHub Actions tests/builds
without signing secrets, then signs and notarizes on a **fresh runner**. Only after
verification succeeds does it publish a ZIP, SHA-256 checksum, and signed Sparkle
appcast together in a GitHub Release. Both bundle versions come from the tag.

Required Actions secrets: `MACOS_CERT_P12` (base64 P12), `MACOS_CERT_PASSWORD`,
`APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `SPARKLE_PRIVATE_KEY`.
Secrets are scoped to their consuming steps. The temporary signing keychain is
deleted after signing; the Sparkle key is read through stdin, never exported to a file.
Only the Sparkle public key is committed. No build caches contain signing material.

Forks must change the certificate pins, feed/repository URLs, and Sparkle public key.
Sparkle verifies the signed feed and archive **before extraction**. Preserve the
dedicated private key: rotating it requires a migration release using a
Developer ID-signed DMG, rather than the current ZIP format.
When upgrading Sparkle, update both its SwiftPM pin and the verified tool-download
version/checksum in the release workflow.

## Google Calendar setup

1. Enable the Google Calendar API in a [Google Cloud project](https://console.cloud.google.com/).
2. Configure the OAuth consent screen and create a **Desktop app** OAuth client.
   In Testing mode, add each account you want to connect as a test user.
3. Download the client JSON, then import it in Don't Miss **Settings**.
4. Connect Google Calendar, grant both read-only permissions, and select calendars.
   Use **Add Google account** for additional accounts.

Keep the client JSON out of source control. Google OAuth apps in Testing mode may
require reconnecting every seven days.

## Usage

Open the menu-bar bell for upcoming meetings and Settings. Alerts appear one minute
before events by default. **Escape** dismisses; Snooze delays an alert by one minute.
All-day and declined events are skipped.
The blurred background respects macOS's Reduce Transparency accessibility setting.

Click an event to preview its alert, join or copy its meeting link, view guests and
notes, or open it in Google Calendar. Mute and custom lead time apply only to that
occurrence, not the entire recurring series. These preferences stay local; the app
does not create or edit calendar events.

Keep the app running: it cannot alert while your Mac is asleep or at the lock screen.
Calendars refresh every minute, with seven days of events cached locally. To use launch
at login, install the app in Applications first.

## License

[MIT](LICENSE) - Copyright (c) 2026 Wouter de Bie.
