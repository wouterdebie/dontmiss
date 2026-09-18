# Don't Miss

A native macOS menu-bar app that makes meetings hard to miss. Built with SwiftUI
and AppKit, inspired by [In Your Face](https://www.inyourface.app/mac/).

**Free and open source.** Website: [dontmiss.now](https://dontmiss.now).
Static website deployment and GCP hosting are documented in [site/README.md](site/README.md).

## Features

- Cyan/blue/purple-accented, frosted-glass alerts on the display containing your mouse pointer.
- Multiple Google accounts with independent calendar selection.
- Day-grouped agenda with Today and Next 7 days views and a slim, edge-aligned scrollbar.
- Clickable event details with guests, notes, meeting links, and local reminder controls.
- Inline Apple Maps previews for event locations that resolve to a specific address or venue.
- Configurable lead time, one-minute snooze, dismissal, and one-click meeting join.
- Offline reminders from a local cache, optional sound, and launch at login.
- Read-only Calendar access; OAuth credentials stay in macOS Keychain.
- Signed updates through Sparkle, with daily checks and user-approved installation.

## Install

Release builds support **Apple Silicon Macs running macOS 14+**.
[Download the latest DMG](https://github.com/wouterdebie/dontmiss/releases/latest/download/DontMiss.dmg),
open it, and drag **Don't Miss** onto the **Applications** folder in the disk image.
Eject the image and open the app from Applications. The DMG and app are signed
and notarized. The ZIP remains available on [GitHub Releases](https://github.com/wouterdebie/dontmiss/releases)
for the in-app updater.
Use **Check for Updates** from the menu or Settings. Automatic checks are on by
default and run once a day while the app is running. You can turn them off in
Settings; an existing opt-out is preserved. Installing an update always requires
your approval.

## Build and run

Requires **macOS 14+** and **Xcode with Swift 6+**. SwiftPM downloads the pinned
[Sparkle](https://sparkle-project.org/) dependency.

```sh
swift package resolve
swift test
bash scripts/bundle.sh
open "dist/Don't Miss.app"
```

Map lookup tests normally use local fixtures. To also verify a public sample address
against Apple's live service, run `DONTMISS_TEST_MAPS=1 swift test --filter EventLocationTests`.

The bundler refuses to replace a running copy of its output. Quit that copy before
rebuilding, or run the installed app in Applications while developing. Replacing a
live app bundle can prevent macOS from authorizing its updater.

Official signing is pinned to the current Developer ID certificate fingerprint in
`scripts/sign.sh`. Set `CODESIGN_IDENTITY` to that fingerprint when bundling;
otherwise signing is ad-hoc. For local notarization, run
`NOTARY_PROFILE="<Keychain profile>" bash scripts/notarize.sh`.

To create a drag-to-Applications disk image from an existing bundle:

```sh
bash scripts/make-dmg.sh "dist/Don't Miss.app" dist/DontMiss.dmg
bash scripts/check-dmg.sh dist/DontMiss.dmg
```

Normal image builds use macOS tools and a checked-in Finder-layout template, so
CI does not need Finder automation or third-party tooling. The optional
`scripts/Brewfile` installs `create-dmg` for reauthoring the layout template.

The image builder refuses to overwrite an existing output and does not change the
source app. A locally built image is a preview, not an official signed/notarized
release. Official releases sign the DMG, run
`bash scripts/notarize.sh dist/download/DontMiss.dmg`, then checksum the final
stapled image.

The app icon shares Davit and Stack's navy/neon visual style. Its editable source
is [Resources/AppIcon.svg](Resources/AppIcon.svg). To regenerate the tracked PNG
and macOS ICNS sizes, run `bash scripts/generate-icon.sh` with `rsvg-convert`
(Homebrew's `librsvg`) installed. This also regenerates the monochrome ringing-bell
menu-bar templates in [Resources/menubar](Resources/menubar), including the
calendar-attention badge and 1x/2x/3x sizes. Normal builds use the tracked images
directly, without needing the renderer. The agenda, Settings, and reminder overlay
reuse the full-color app icon and its palette, with darker accents for light mode.

## Releases

Push a `vMAJOR.MINOR.PATCH` tag on a commit from `main`. GitHub Actions tests/builds
without signing secrets, then signs and notarizes on a **fresh runner**. Only after
verification succeeds does it publish a signed/notarized `DontMiss.dmg`, the ZIP,
SHA-256 checksums for both, and the signed Sparkle appcast together in a GitHub
Release. Both bundle versions come from the tag.

The DMG always uses the stable asset name `DontMiss.dmg`, so the website's
`/releases/latest/download/DontMiss.dmg` link downloads the newest release directly.
It has a drag-to-Applications layout and is verified by mounting it read-only in
CI. The DMG lives in `dist/download`, separate from `dist/release`, so Sparkle's
appcast generator only sees the ZIP and the existing update channel stays intact.

CI also uploads and downloads the unsigned bundle through the pinned artifact
actions, verifying archive integrity, executable permissions, framework symlinks,
and code signatures before those actions are used in a release. CI also builds
and checks the DMG layout without release credentials.

Required Actions secrets: `MACOS_CERT_P12` (base64 P12), `MACOS_CERT_PASSWORD`,
`APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `SPARKLE_PRIVATE_KEY`.
Secrets are scoped to their consuming steps. The temporary signing keychain is
deleted after app and DMG signing, including on failure; the Sparkle key is read through stdin, never exported to a file.
Only the Sparkle public key is committed. No build caches contain signing material.

Before certificate signing or notarization, releases prove that the supplied Sparkle
private key can sign a test payload verifiable with `SUPublicEDKey` in
`Resources/Info.plist`. The bundled public key must match that pin too. A mismatch
fails the release rather than generating or replacing any key. The same preflight
runs in `scripts/sign-release.sh` before generating the appcast.

For local release signing after notarizing and archiving, run
`VERSION="1.2.3" bash scripts/sign-release.sh /path/to/sparkle-tools/bin` with
`SPARKLE_PRIVATE_KEY` supplied through your secret manager's environment.
The script passes the key on stdin, never through arguments or a key file.
It does not read or modify Keychain. Do not run `generate_keys` to resolve a
missing-key error: restore the existing key that matches the committed public key.
Run `swift scripts/test-sparkle-key.swift` to test this guard using disposable
in-memory keys and the pinned Sparkle tools, without accessing your signing key.

Forks must change the certificate pins, feed/repository URLs, and Sparkle public key.
Sparkle verifies the signed feed and archive **before extraction**. Preserve the
dedicated private key: rotating it requires a migration release using a
Developer ID-signed DMG in the update feed, rather than the current ZIP update format.
Publishing a human-download DMG does not by itself change that update channel.
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

Event details look up physical locations using Apple Maps and show an inline map
when a single specific address or venue is returned. Click the map or **Open in
Apple Maps** to open that place in Maps. Obvious online locations, meeting URLs,
and simple room labels are skipped. Unresolved or ambiguous locations keep their
original text with an explanation; failed lookups can be retried.
Lookup requires an internet connection and sends the event's location text to
Apple when you open event details. It does not request or use your device's location.
Search results are not a guarantee that an address is correct; check the displayed
place before traveling.

Keep the app running: it cannot alert while your Mac is asleep or at the lock screen.
Calendars refresh every minute, with seven days of events cached locally. To use launch
at login, install the app in Applications first.

## License

[MIT](LICENSE) - Copyright (c) 2026 Wouter de Bie.
