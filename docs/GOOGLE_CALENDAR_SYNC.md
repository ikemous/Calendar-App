# Google Calendar sync

The app can sync two ways with Google Calendar. There are two routes, and
the app picks one automatically:

| Route | Setup | Used when |
| --- | --- | --- |
| **Phone calendar** (Android) | None | No Google client IDs are in `google_config.dart`. This is the default |
| **Direct Google sign-in** | Google Cloud project and client IDs (below) | Client IDs have been added. Also the only route on iOS |

## The easy route: sync through the phone's calendar (Android)

Android keeps the calendars of every Google account on the phone in step
with Google by itself. The app syncs with one of those calendars, so events
reach Google Calendar without the app ever signing in to Google.

For the user:

1. The Google account must be on the phone (Settings → Passwords &
   accounts) with **Calendar** sync switched on. It usually already is.
2. In the app: Settings → Google Calendar → **Choose a calendar to sync**.
3. Allow calendar access when Android asks, pick the calendar, confirm.

What to know:

- **Timing.** The app syncs with the phone's calendar when it is opened,
  after an event changes, and on **Sync now**. Android then exchanges
  changes with Google on its own schedule, usually within a few minutes;
  the app does not control that part.
- **Conflicts.** The phone's calendar does not record when an event was
  last changed, so if the same event was edited in both places, the edit
  made in this app is kept.
- **App-only fields.** Notes, priority, colour and category stay in this
  app; the phone's calendar has nowhere to store them, so they do not
  reach other devices.
- **Any calendar works**, not only Google ones (for example a calendar
  that exists only on the phone, or an Exchange account's).
- **Not on iOS yet.** The equivalent there (EventKit) is not implemented.

How it is built: `DeviceCalendar.kt` reads and writes raw rows of Android's
Calendar Provider. `DeviceCalendarApi` (`features/sync/services/
device_calendar.dart`) translates those rows to and from the shape the sync
engine already uses for Google, so the same engine and conflict rules
apply. Android gives ordinary apps no change feed, so changes are found by
comparing a fingerprint of each event with the one saved at the previous
sync. `test/unit/device_calendar_sync_test.dart` runs the real engine
against an in-memory phone calendar.

Permissions: `READ_CALENDAR` and `WRITE_CALENDAR`, requested only when the
user taps **Choose a calendar to sync**.

## Direct Google sign-in

The rest of this document describes the direct route. It is **switched off
until you add Google client IDs**, which only you can create (they belong
to your Google Cloud project).

## One-time setup (about 10 minutes, free)

### 1. Create a Google Cloud project

1. Open <https://console.cloud.google.com/> and create a project.
2. **APIs & Services → Library** → search for **Google Calendar API** →
   **Enable**.

### 2. Configure the consent screen

**APIs & Services → OAuth consent screen** (also called *Google Auth
Platform*):

1. User type **External**. Fill in the app name and your email.
2. **Data access / Scopes** → add
   `https://www.googleapis.com/auth/calendar.events`.
3. **Audience / Test users** → add the Google accounts you will test with.
   While the app is in *Testing* status, only these accounts can sign in.

### 3. Create three OAuth client IDs

**APIs & Services → Credentials → Create credentials → OAuth client ID**,
three times:

| Type | Fields | Used for |
| --- | --- | --- |
| **Web application** | Name only | Its client ID is the `serverClientId` the app passes to Google sign-in. Required on Android |
| **Android** | Package name `com.ikemous.calendar_app` (or your own app id) and the **SHA-1** of your signing certificate | Lets your Android build sign in. It is matched automatically; you do not paste this ID anywhere |
| **iOS** | Bundle ID (same as in Xcode) | Its client ID goes in the app, and its reversed form in `Info.plist` |

Getting the Android SHA-1:

```sh
# Debug builds (what `flutter run` uses)
keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android

# Your release/upload keystore
keytool -list -v -alias upload -keystore <path to upload-keystore.jks>
```

On Windows the debug keystore is `%USERPROFILE%\.android\debug.keystore`.

Create **one Android client per certificate**: one for debug, one for your
upload key, and, once the app is on Google Play, one for the *App signing
key* shown in Play Console → Setup → App signing. A missing or wrong SHA-1
is the usual reason sign-in fails on Android.

### 4. Put the IDs in the app

1. `lib/app/config/google_config.dart`:

   ```dart
   static const String serverClientId = '<Web client ID>';
   static const String iosClientId = '<iOS client ID>';
   ```

   Client IDs are identifiers, not secrets; they are safe to commit. Do not
   put a client *secret* in the app (none is needed).

2. `ios/Runner/Info.plist`: replace
   `com.googleusercontent.apps.REPLACE_WITH_IOS_CLIENT_ID` with the iOS
   client ID **reversed**. For the ID
   `1234-abc.apps.googleusercontent.com` that is
   `com.googleusercontent.apps.1234-abc`.

3. Rebuild. Settings → Google Calendar now offers **Connect Google
   account**.

### 5. Before releasing to the public

`calendar.events` is a *sensitive* scope. To let anyone (not just your test
users) sign in, set the consent screen to **In production** and submit it
for Google's verification: a privacy policy URL, a homepage, and a short
explanation/video of how the app uses calendar data. Unverified apps show a
warning screen and are capped at 100 users.

Also update your store listings: the Play **Data safety** form and App
Store **App Privacy** answers change from "no data collected" to reflect
that calendar events are sent to Google at the user's request.

## What sync does

- **Which calendar:** the account's primary calendar only.
- **When:** on app start, when the app returns to the foreground, a few
  seconds after any local event change, and on **Sync now**. It does not run
  while the app is closed.
- **First connect:** Google's events are downloaded and the events already
  in the app are uploaded. The user is told this and must confirm.
- **Afterwards:** creations, edits and deletions on either side are copied
  to the other.
- **Conflicts:** if an event changed in both places, the more recent change
  wins.
- **Offline:** changes wait on the device and are sent on the next
  successful sync.
- **Disconnect:** stops syncing; nothing is deleted on either side.
  Reconnecting the same account merges without duplicates. Connecting a
  different account treats existing local events as new for that account.
- **Erase all data / restore-with-replace:** never deletes anything from
  Google. If an account is connected, the next sync downloads its events
  again.

### Field mapping

| App | Google |
| --- | --- |
| Title, description, location | `summary`, `description`, `location` |
| Start/end, all-day | `start`/`end` (`dateTime` + time zone, or `date` with an exclusive end) |
| Repeat rule, excluded dates | `recurrence` (`RRULE`, `EXDATE`) |
| Reminders | `reminders.overrides` as popups (Google allows at most 5, up to 4 weeks ahead). Google's calendar default reminders are used for events that say "use default" |
| Notes, priority, colour, category | Private extended properties: stored with the event, visible only to this app, restored on other devices |
| Tasks | Not synced |

### Limits to know about

- **Repeat rules the app cannot represent** (for example "the 1st and 15th
  of each month", or anything using `BYSETPOS`) are shown on their first
  date only. The rule is left untouched in Google, even if the event is
  edited in the app. The sync result reports how many such events exist.
  Daily, weekly (any weekdays), monthly by date, monthly by "nth weekday"
  and yearly rules, with an interval, end date or count, are supported.
- **Edited single dates of a series** made in the app are stored in Google
  as a separate event plus an excluded date on the series (the visible
  result is the same). Edits to single dates made in Google arrive as
  detached events in the app.
- **A date restored in Google** after having been removed from a series
  stays hidden in the app.
- **Time zones:** times are shown in the device's zone. A recurring event
  created in another zone with different daylight-saving rules can be an
  hour off for part of the year.
- **Guests, video links and other Google-only fields** are neither shown
  nor altered: updates only send the fields the app owns.
- **Double notifications:** if the Google Calendar app is installed too,
  both apps may notify for the same event. Turn reminders off in one.

## How it is built

```
lib/features/sync/
  services/
    calendar_auth.dart          sign-in and access tokens (interface + Google)
    remote_calendar_api.dart    the four API calls sync needs (interface + HTTP)
    google_event_mapper.dart    event <-> Google JSON, RRULE parsing
    sync_engine.dart            pull, conflict rules, push
  providers/sync_controller.dart  connect/disconnect, when to sync, status
  screens/google_sync_screen.dart
```

- Each event stores its Google id, etag and the time it was last in step
  (`remote_id`, `remote_etag`, `synced_ms`). An event needs uploading when
  it has no Google id or was updated after that time.
- Deleting a linked event records its Google id in `sync_deletions` until
  the delete has been sent.
- Pull uses Google's incremental **sync token**; if Google expires it, the
  engine lists everything again and merges by id.
- The engine depends only on the `RemoteCalendarApi` and `CalendarAuth`
  interfaces. `test/sync_fakes.dart` provides an in-memory Google Calendar,
  and `test/unit/google_sync_test.dart` runs the engine against it.

## Testing against real Google

The automated tests use the in-memory fake; they do not prove that Google
itself accepts every request. After adding your client IDs, check by hand
with a **test calendar account**:

1. Connect; confirm existing events appear on both sides.
2. Create, edit and delete an event in the app → check calendar.google.com.
3. Create, edit and delete an event in Google → tap **Sync now**.
4. Repeat with an all-day event, a weekly series, deleting one date of a
   series on each side, and an event with two reminders.
5. Turn on airplane mode, edit an event, turn it off, sync.
