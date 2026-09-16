# Don't Miss

A native macOS menu-bar app that interrupts you before a meeting. Built with SwiftUI
and AppKit, with direct, read-only Google Calendar integration and no dependencies
outside Apple's frameworks.

Inspired by the core behavior of [In Your Face](https://www.inyourface.app/mac/):
full-screen meeting alerts, snoozing and quick joining. This is an independent MVP,
not a clone of its design or an implementation of all its features.

## MVP

- Opaque reminders only on the display containing your mouse pointer when the
  alert fires, including normal full-screen Spaces. Other displays stay usable.
- Alert from 0 to 30 minutes before an event; default one minute.
- Dismiss, snooze for one minute, or join the video call. Escape dismisses.
- Sequential reminders when meetings overlap, so one does not overwrite another.
- Multiple Google accounts through OAuth in your system browser; choose calendars
  independently for each account. Adding the same account again reconnects it.
- Recurring events expanded by Google, with time zones/UTC offsets respected.
- Excludes all-day, cancelled, personally declined, focus-time, out-of-office,
  working-location and birthday events. Timed events without a meeting link still alert.
- Detects Google conference links and common Meet, Zoom, Teams, Webex, Whereby
  and Jitsi links in event descriptions/locations.
- One-minute calendar polling; caches the next 48 hours for offline reminders.
- Persistent dismiss/snooze state; moving an event to a new time re-arms its alert.
- Optional sound and start at login.
- A test alert that needs no Google account.

No Apple Calendar access, Accessibility permission, Screen Recording permission or
notification permission is needed for the overlay.

## Build and run

Requires macOS 14+, Xcode/Swift 6+, and the macOS SDK.

```sh
swift test
bash scripts/bundle.sh
open "dist/Don't Miss.app"
```

Open this folder in VS Code to use the build/test/bundle tasks, or open
`Package.swift` in Xcode. The executable needs its `.app` bundle for normal use;
prefer the bundled application over `swift run`, especially for Keychain and login items.

The bell appears in your menu bar. Open Settings, import an OAuth client, connect
Google Calendar, and select calendars. Try **Show test alert on this display**.
The alert takes over the screen until you dismiss, snooze or join; Escape always
offers an exit. Snoozing a preview simply closes it and does not schedule a real reminder.

An alert stays on the display selected at firing time rather than chasing the
pointer. If that display is disconnected, it moves to the current mouse display,
falling back to the main display when necessary. This needs no Accessibility permission.

Use **Add Google account** to connect another account with the same OAuth client.
Google's account chooser lets you select a different login. Each account has its
own refresh/access tokens, calendar selections, cache and sync status. Disconnect
removes only that account; other accounts and their reminders continue working.
The original single-account installation migrates automatically on first launch.
If one account's refresh fails, its cached reminders remain active while the other
accounts continue syncing. In Google OAuth Testing mode, add every account you
want to connect to the project's test-user list.

For a stable login-item location, copy the signed app to `~/Applications` or
`/Applications`, launch that copy, then enable **Start Don't Miss at login**.
Do not run development and installed copies at the same time.

### Signing

The bundle script follows the Developer ID + hardened runtime approach used by
ContainerStack/Davit. Supply the **certificate fingerprint**, not its common name:
multiple certificates can have the same display name.

```sh
security find-identity -v -p codesigning
CODESIGN_IDENTITY="<Developer ID Application certificate SHA-1>" bash scripts/bundle.sh
```

Without an identity the script explicitly uses ad-hoc signing for local development.
There is no App Sandbox entitlement: the application needs the browser OAuth
loopback listener and Calendar network access. The hardened runtime remains enabled
on Developer ID builds. Credentials are never bundled.

For distribution, store notarization credentials in Keychain using Apple's
`xcrun notarytool store-credentials` flow, then:

```sh
NOTARY_PROFILE="<your Keychain profile>" bash scripts/notarize.sh
```

This submits the ZIP, waits for notarization, staples the ticket to the app and
checks Gatekeeper. Unlike ContainerStack's CI polling helper, this local-only
script uses `--wait`; a network interruption is surfaced rather than hidden.
Notarization is separate from local code signing.

## Google Cloud setup

Use project **wouterdebie-personal**. Its Google Calendar API was confirmed enabled
during setup. No new project, service account, billing changes or API keys are needed.

1. In [Google Auth Platform](https://console.cloud.google.com/auth/overview?project=wouterdebie-personal),
   configure the app branding/consent screen. Name it **Don't Miss**.
2. If the audience is External and publishing status is Testing, add the Google
   account whose calendar you will connect as a test user.
3. Under [Clients](https://console.cloud.google.com/auth/clients?project=wouterdebie-personal),
   create an OAuth client of type **Desktop app**, not Web application.
4. Download the client JSON somewhere outside this repository.
5. Import it in Don't Miss Settings, then click **Connect Google Calendar**.
6. Grant both read-only permissions:
   - `https://www.googleapis.com/auth/calendar.events.readonly`
   - `https://www.googleapis.com/auth/calendar.calendarlist.readonly`

The app uses Google's [installed-app OAuth flow](https://developers.google.com/identity/protocols/oauth2/native-app)
with a random loopback port on `127.0.0.1`, PKCE/S256 and state validation.
OAuth client configuration and refresh credentials are stored in macOS Keychain.
An installed-app client secret is not a confidential server credential, but keep
the downloaded file out of source control anyway.

The personal project's existing consent-screen name is **node-red-background**.
That name may appear in Google's unverified-app warning even though this Desktop
client is Don't Miss. Branding is shared across OAuth clients in a project; changing
it can affect existing applications. For this personal installation, confirm the
developer is your own account before proceeding through Google's warning.

**Testing-mode caveat:** external Google OAuth apps in Testing generally issue
refresh tokens that expire after seven days for these Calendar scopes. You may
need to reconnect weekly until you change the publishing status. Publishing or
distributing beyond personal use may introduce Google's verification requirements;
Don't Miss does not change your consent-screen settings automatically.

To import from a local file on launch (no credentials are printed):

```sh
open "dist/Don't Miss.app" --args --import-oauth "/absolute/path/to/client.json" --settings
```

This only takes effect on a fresh launch. Disconnect before replacing a client.
Disconnect revokes authorization where possible and clears that account's local
calendar/token state; the OAuth client remains available for reconnecting.

## Reliability and limitations

- **Keep the app running.** It cannot show an alert while the Mac sleeps, is off,
  or at the secure lock screen. It does not block system shortcuts or trap you.
- On wake it refreshes and catches up on unacknowledged events that started no more
  than 10 minutes ago and have not ended. Older events do not produce a flood of alerts.
- Polling means Google changes can take about a minute to arrive. During outages,
  cached events still alert and may include since-cancelled or moved meetings.
  The UI displays failures and a stale-schedule warning after five minutes.
- The offline cache covers 48 hours from the last successful refresh. After that,
  reconnecting is necessary to obtain new events.
- A failed refresh does not replace the previous schedule with an empty one.
- A snoozed event may alert beyond the 10-minute catch-up window, but never after
  the event ends. Dismiss/Join acknowledges only that event at that start time.
- The same calendar/event/start visible through multiple accounts is deduplicated.
  Separate invitation copies on different calendars are still separate reminders.
- No Microsoft/iCloud providers,
  custom reminders, automatic updates, fancy themes or calendar editing in this MVP.
- A meeting's **video** conference entry must be HTTPS; only trusted conferencing
  hostnames are extracted from free text. Arbitrary URL schemes are never opened.
- Reminder state and event titles/links are stored locally in
  `~/Library/Application Support/dev.wouter.dontmiss/schedule.json` with owner-only
  permissions. No analytics or external backend. Disconnect clears that account's cache.

## Validation

```sh
swift test
plutil -lint Resources/Info.plist
bash -n scripts/bundle.sh scripts/notarize.sh
"dist/Don't Miss.app/Contents/MacOS/DontMiss" --smoke-test
```

The last command briefly shows exactly one real overlay on the mouse's display,
checks its visibility, full-screen frame, window level and Space behavior flags, then exits. It
does not connect to Google or modify saved reminder state.

Unit tests cover alert boundaries, wake catch-up, snooze persistence, moved and
recurring events, overlap ordering, filtering, date parsing, URL safety, pagination,
request parameters and explicit Calendar API errors, plus OAuth helpers.
For end-to-end acceptance, connect your account, create a short timed event on a
selected calendar, refresh, and confirm the overlay, Snooze, Dismiss and Join.
Also check another full-screen app and external monitors; macOS focus/Space policy
is not fully verifiable by a unit test.

Initial verification on September 16, 2026: browser OAuth completed and Google
returned 10 calendars. The existing connection and calendar selections migrated
successfully to per-account storage without reconnecting. Notarization and a real
scheduled-meeting end-to-end test remain separate acceptance steps.
# dontmiss
