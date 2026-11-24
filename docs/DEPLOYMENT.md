# Building and deploying

All commands run from the project root. Run `flutter doctor` first and fix
anything it reports for the platform you are building.

The version comes from `pubspec.yaml`: `version: 1.0.0+1` is version name
`1.0.0` and build number `1`. Both stores require the build number to
increase with every upload. You can also override them per build with
`--build-name=1.0.1 --build-number=2`.

## Application id

The id is currently `com.ikemous.calendar_app`. Stores never let you change
it after the first upload, so set your own first:

- Android: `applicationId` and `namespace` in `android/app/build.gradle.kts`,
  and move `MainActivity.kt` to the matching package folder (update its
  `package` line).
- iOS: `PRODUCT_BUNDLE_IDENTIFIER` in Xcode (Runner target → Signing &
  Capabilities).

---

## Android

Requires JDK 17 and the Android SDK. The first build downloads the SDK
platform, build tools and NDK it needs.

### Development build

```sh
flutter devices
flutter run -d <device-id>
```

### Debug APK

```sh
flutter build apk --debug
# build/app/outputs/flutter-apk/app-debug.apk
```

### Release signing (one-time setup)

1. Create an upload keystore. Keep it and its passwords somewhere safe and
   backed up; without it you cannot update the app.

   ```sh
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Create `android/key.properties` (already git-ignored, never commit it):

   ```properties
   storePassword=<store password>
   keyPassword=<key password>
   keyAlias=upload
   storeFile=<absolute path to upload-keystore.jks>
   ```

`android/app/build.gradle.kts` picks this file up automatically. Without it,
release builds are signed with the debug key: fine for trying a release build
on your own device, but Google Play rejects them.

### Release APK

```sh
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk

flutter build apk --release --split-per-abi   # smaller, one APK per CPU type
```

### Android App Bundle

```sh
flutter build appbundle --release
# build/app/outputs/bundle/release/app-release.aab
```

### Google Play

1. Create the app in [Play Console](https://play.google.com/console) and
   complete the store listing, content rating, target audience and Data
   safety form. Without Google sync the app collects and shares no data;
   with it, calendar events are sent to Google at the user's request (see
   [GOOGLE_CALENDAR_SYNC.md](GOOGLE_CALENDAR_SYNC.md)).
2. Upload `app-release.aab` to an internal testing track first, then promote
   it to closed/open testing and production.
3. Accept Play App Signing when prompted; your keystore becomes the upload
   key.
4. **Exact alarms declaration.** The manifest requests `USE_EXACT_ALARM` so
   reminders arrive on time. Play Console asks you to declare why; choose
   the calendar/alarm use case. If you would rather not declare it, remove
   that permission from `AndroidManifest.xml`; the app then falls back to
   inexact delivery on Android 13+ (reminders may arrive a few minutes late).

### Android permissions and notification setup

Declared in `android/app/src/main/AndroidManifest.xml`:

| Permission | Why |
| --- | --- |
| `INTERNET` | Google Calendar sync only |
| `READ_CALENDAR`, `WRITE_CALENDAR` | Sync with a calendar on the phone. Requested only when the user connects one. Declare calendar access in the Play Data safety form |
| `POST_NOTIFICATIONS` | Show reminders and lock screen events. Requested at runtime (Android 13+) the first time a reminder is saved, after an in-app explanation |
| `RECEIVE_BOOT_COMPLETED` | Restore scheduled reminders after a restart |
| `USE_EXACT_ALARM`, `SCHEDULE_EXACT_ALARM` (API ≤ 32) | Deliver reminders at the exact time |

Also required by the notifications plugin and already configured: the two
`<receiver>` entries in the manifest, core library desugaring and
`compileSdk 37` in `build.gradle.kts`, the GSON rules in
`proguard-rules.pro`, the `ic_notification` icon and its `res/raw/keep.xml`
entry.

Some manufacturers (Xiaomi, Huawei, Oppo, Samsung) stop background work
aggressively. If reminders are missed on such a device, exempt the app from
battery optimisation in system settings.

---

## iOS and iPadOS

**iOS builds cannot be made on Windows or Linux.** Compiling, signing and
uploading need macOS with Xcode, or a hosted macOS build service (Codemagic,
GitHub Actions `macos` runners, Bitrise, Xcode Cloud). The included
`.github/workflows/ci.yml` builds the iOS app unsigned on a macOS runner on
every push, which verifies that it compiles.

You also need an [Apple Developer Program](https://developer.apple.com/programs/)
membership to install on devices beyond a 7-day personal build, and for
TestFlight and the App Store.

### One-time setup (on the Mac)

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
flutter doctor
open ios/Runner.xcworkspace
```

In Xcode, select the **Runner** target → **Signing & Capabilities**: choose
your Team, set your Bundle Identifier and leave "Automatically manage
signing" on.

### iOS simulator

```sh
open -a Simulator
flutter run
```

Notifications can be scheduled in the simulator. Choose an iPad simulator to
check the tablet layout.

### Physical iPhone or iPad

1. Connect the device, trust the computer, and enable Developer Mode on the
   device (Settings → Privacy & Security → Developer Mode).
2. `flutter devices`, then `flutter run -d <device-id>`. Add `--release` to
   test real-world performance and reminders with the app closed.
3. With a free Apple ID, open Settings → General → VPN & Device Management on
   the device and trust your developer certificate.

Test on both an iPhone and an iPad: the app is universal, supports all
orientations on iPad, and uses a navigation rail and two-pane layouts on the
larger screen.

### Release build and IPA

```sh
flutter build ipa --release
# build/ios/ipa/*.ipa and build/ios/archive/Runner.xcarchive
```

This archives and exports with your signing settings. To check that the app
compiles without signing (for example in CI): `flutter build ios --release --no-codesign`.

### TestFlight

1. Create the app record in [App Store Connect](https://appstoreconnect.apple.com)
   with the same bundle identifier.
2. Upload the IPA using the Transporter app, or from Xcode: Window →
   Organizer → select the archive → Distribute App → App Store Connect.
   From the command line:

   ```sh
   xcrun altool --upload-app --type ios -f build/ios/ipa/*.ipa --apiKey <key id> --apiIssuer <issuer id>
   ```

3. Wait for processing, then add internal testers under the TestFlight tab.
   External testers need a short beta review.

### App Store

1. In App Store Connect, complete the listing: screenshots for iPhone and
   iPad, description, support URL, privacy policy URL and age rating.
2. App Privacy: "Data Not Collected" applies only if you ship without
   Google sync. With sync, declare calendar data as used for app
   functionality.
3. Select the processed build, then Submit for Review.

### iOS permissions, configuration and notifications

- **Notifications** are local, so no push capability, APNs key or
  entitlement is needed. Permission is requested at runtime the first time a
  reminder is saved (after an in-app explanation), not at launch. iOS has no
  Info.plist usage string for notification permission.
- `ios/Runner/AppDelegate.swift` sets the `UNUserNotificationCenter`
  delegate so reminders can be shown while the app is open and taps open
  the right event.
- iOS keeps at most 64 pending local notifications per app. The app
  schedules the soonest 56 reminders plus up to 8 lock screen hand-overs,
  and refreshes them each time it is opened.
- `ITSAppUsesNonExemptEncryption` is `false` in `Info.plist` (the app uses
  no encryption), which skips the export-compliance question on each upload.
- No other usage descriptions are required: backup/restore uses the system
  document picker and share sheet, which need no permission.
- Deployment target: iOS 15.0.

---

## Release checklist

- [ ] Application id / bundle identifier set to your own
- [x] Launcher icon set on both platforms (generated from
      `assets/icon/app_icon.png`; to change it, replace that file and
      regenerate the sizes in `android/app/src/main/res/mipmap-*` and
      `ios/Runner/Assets.xcassets/AppIcon.appiconset`)
- [ ] Google sync: client IDs added, Android SHA-1s registered, consent
      screen verified (or sync left switched off)
- [ ] Version and build number increased in `pubspec.yaml`
- [ ] `flutter analyze` and `flutter test` pass
- [ ] `integration_test` passes on an Android device and an iOS device
- [ ] Lock screen: the featured repeating event and the next event checked
      on a locked real device, including hand-overs with the app closed
- [ ] Reminders checked on real devices with the app closed, and after a
      restart (Android)
- [ ] Android: `key.properties` present, AAB built and uploaded
- [ ] iOS: archive built on macOS, uploaded to TestFlight and tested on
      iPhone and iPad
