# Calendar

A private, offline-first calendar for Android phones and tablets, iPhone and
iPad, built from a single Flutter codebase.

- Month, week, day, year and agenda views
- Events with recurrence (daily, weekly, every two weeks, monthly, yearly,
  custom), reminders, categories, colours, priority, location and notes
- Edit or delete one occurrence, this and future occurrences, or a whole series
- Local notifications that fire when the app is closed
- Tasks with due dates, priorities and reminders, shown inside the calendar
- Search across events and tasks
- JSON backup and restore, CSV and iCalendar (.ics) export
- Light, dark and system themes; phone and tablet layouts
- Lock screen: a live countdown to one featured repeating event, or to
  your next event (see *Lock screen* below)
- Optional two-way sync with Google Calendar: on Android, pick a calendar
  already on the phone and it just works (see
  [docs/GOOGLE_CALENDAR_SYNC.md](docs/GOOGLE_CALENDAR_SYNC.md))
- Everything is stored on the device in SQLite. No account is required and
  the network is used only if Google sync is connected.

## Requirements

| Tool | Version |
| --- | --- |
| Flutter | stable, 3.50 or newer (Dart 3.14+) |
| Android | JDK 17, Android SDK with platform 37 (installed automatically on first build) |
| iOS | macOS with a current Xcode (whatever `flutter doctor` accepts). iOS builds cannot be produced on Windows or Linux |

Minimum OS versions: Android 7.0 (API 24), iOS/iPadOS 15.

## Run

```sh
flutter pub get
flutter run                 # on a connected device, emulator or simulator
```

## Test

```sh
flutter analyze
flutter test                                              # unit + widget tests
flutter test integration_test/app_test.dart -d <device>   # end-to-end, on a device
```

| Suite | Covers |
| --- | --- |
| `test/unit/date_and_recurrence_test.dart` | date and time calculations, recurring events, overlap layout |
| `test/unit/events_test.dart` | event creation, editing, deletion; series edit/delete scopes |
| `test/unit/notifications_test.dart` | reminder planning; reschedule on edit, cancel on delete |
| `test/unit/storage_test.dart` | SQLite persistence across restarts, categories, import/export |
| `test/unit/tasks_and_search_test.dart` | task management, search |
| `test/unit/device_calendar_sync_test.dart` | sync with the phone's calendar: both directions, repeats, conflicts |
| `test/unit/lock_screen_test.dart` | lock screen notification cards |
| `test/unit/countdown_widgets_test.dart` | data for the two countdown widgets |
| `test/unit/google_sync_test.dart` | two-way sync against an in-memory Google Calendar, rule parsing, database upgrade |
| `test/widget/app_test.dart` | responsive layouts on five screen sizes, navigation, event/task/search/settings flows |
| `integration_test/app_test.dart` | full flows against the real database on a device |

## Build and release

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for Android (APK, App Bundle,
Google Play) and iOS (simulator, device, IPA, TestFlight, App Store)
instructions, including signing, permissions and notification setup.

## Project layout

```
lib/
  main.dart                 startup: open database, set up notifications
  app/                      MaterialApp, router, navigation shell, theme
  core/
    database/               SQLite schema and migrations
    notifications/          notification service, reminder planning/scheduling
    services/               export (JSON/CSV/ICS), file hand-off, app wiring
    utilities/              date maths, formatting, ids
  data/
    models/                 CalendarEvent, RecurrenceRule, Task, Category, AppSettings
    repositories/           storage interfaces
    datasources/            SQLite implementations, sync extension point
  features/
    calendar/               views, calendar state, recurrence engine, overlap layout
    events/                 detail and edit screens, series editing rules
    sync/                   Google sign-in, API client, mapping, sync engine
    tasks/  categories/  search/  settings/
  shared/                   widgets and helpers used by several features
```

### How the pieces fit

- **State** is held by Riverpod notifiers (`eventsProvider`, `tasksProvider`,
  `categoriesProvider`, `settingsProvider`). They load once at startup and
  write every change through to a repository.
- **Storage** is behind the interfaces in `data/repositories/`. The app only
  uses those interfaces; `data/datasources/sqlite_repositories.dart` is the
  SQLite implementation.
- **Recurrence** is computed, not stored: one row per series, expanded on
  demand by `RecurrenceEngine`. Exceptions are stored as excluded dates and
  detached events.
- **Notifications** are replanned from scratch after every change
  (`ReminderPlanner` → `ReminderScheduler`), which is what makes edits
  reschedule and deletes cancel. Only the soonest 56 are handed to the OS
  (iOS allows 64 pending); the window rolls forward each time the app opens.
- **Schema changes**: bump `AppDatabase.schemaVersion` and add a step to
  `_onUpgrade` so existing installs keep their data.

### Lock screen

The lock screen shows one event with a live countdown:
`[picture] Anniversary ❤️   100d 20:20:59` (days, then hours:minutes:seconds,
ticking every second).

- **Featured event**: one repeating event of your choice, counting down to
  its next occurrence. Open the event and tap the pin (only repeating events
  have one); pinning another replaces it. Settings → Notifications shows
  which event is featured.
- **Next event** (Settings → Notifications, on by default): if no event is
  featured, the card counts down to the next upcoming event instead.

- **Picture** (Settings → Notifications → Lock screen picture): a picture
  of your choice shown beside the featured event. Without one, the card
  has no image. It is picked with the system photo picker (no storage permission),
  and only a small copy is kept in the app's private storage. It is not
  part of backups or Google sync.

Once the event starts the card reads "Now" (or "Today" for an all-day
event) until it ends, then moves on. Only the title and countdown are
shown, never the description or notes. It needs the Reminders switch on and
notification permission.

**Android.** The card is one silent, persistent notification with a
custom layout, because a notification is the only thing
every Android phone shows on the lock screen. (It therefore also appears in
the notification shade; Android has no lock-screen-only surface.)
`CountdownPlanner` (`lib/core/home_widgets/`) builds, for each countdown,
the list of entries that take over from one another, and
`ReminderScheduler` sends it to `CountdownWidgets.kt` after every change.
The native code picks the current entry and shows the whole days as text
plus a system `Chronometer` for the rest, which ticks by itself. An alarm
redraws the card each time a full day has run down and when the event
starts or ends, so it stays right while the app is closed. It is redrawn after a restart, an app update and a
clock or time zone change. Tapping it opens the app.

The same data feeds two app widgets declared for the lock screen only
(`widgetCategory="keyguard"`), for phones that let you place widgets there;
they are not offered for the home screen.

**iOS.** There is no native lock screen display yet. The app falls back to
`LockScreenPlanner`, which posts ordinary quiet notifications ("Featured" /
"Next") that stay in the lock screen list until dismissed. Real iOS lock
screen widgets need a WidgetKit extension written in Swift and added in
Xcode on a Mac; `CountdownWidgetService` is the interface it would plug
into.

### Google Calendar sync

`features/sync/` implements two-way sync. On Android it works with no
setup, through a calendar already on the phone (Settings → Google Calendar
→ Choose a calendar to sync): Android itself keeps a Google account's
calendar in step with Google. Adding Google client IDs to
`lib/app/config/google_config.dart` switches to direct Google sign-in,
which is also the only route on iOS. Both routes, their behaviour and
limits are in [docs/GOOGLE_CALENDAR_SYNC.md](docs/GOOGLE_CALENDAR_SYNC.md).

The engine talks to the calendar only through two small interfaces
(`RemoteCalendarApi`, `CalendarAuth`); the phone calendar and Google are
two implementations of them.

## Privacy

Calendar data stays on the device unless the user exports it or connects
a calendar. With a phone calendar connected, events are written to that
calendar, where other calendar apps on the phone can see them and where
the phone syncs them to the calendar's account. With Google connected, events (not tasks) are exchanged
directly between the device and Google using the `calendar.events` scope.
There are no analytics and no account is required. Notification text
contains the title, time and location only. Backup files are plain JSON and
are not encrypted.

## Before publishing

- The app id is `com.ikemous.calendar_app`. Change it to an id you own before
  the first store upload (it cannot be changed afterwards); see
  [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md#application-id).
- The launcher icon is the Flutter default. Replace it for both platforms.
