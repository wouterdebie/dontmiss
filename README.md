# Don't Miss

A native macOS menu-bar app that makes meetings hard to miss. Built with SwiftUI
and AppKit, inspired by [In Your Face](https://www.inyourface.app/mac/).

## Features

- Mint-accented, frosted-glass alerts on the display containing your mouse pointer.
- Multiple Google accounts with independent calendar selection.
- Day-grouped agenda with Today and Next 7 days views.
- Clickable event details with guests, notes, meeting links, and local reminder controls.
- Configurable lead time, one-minute snooze, dismissal, and one-click meeting join.
- Offline reminders from a local cache, optional sound, and launch at login.
- Read-only Calendar access; OAuth credentials stay in macOS Keychain.

## Build and run

Requires **macOS 14+** and **Xcode with Swift 6+**. No third-party dependencies.

```sh
swift test
bash scripts/bundle.sh
open "dist/Don't Miss.app"
```

Set `CODESIGN_IDENTITY` to your Developer ID certificate fingerprint when bundling
for signed builds; otherwise signing is ad-hoc. For notarization, run
`NOTARY_PROFILE="<Keychain profile>" bash scripts/notarize.sh`.

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
