/// Google sign-in configuration for Google Calendar sync.
///
/// Sync stays switched off until these are filled in. Create the ids in the
/// Google Cloud console (see docs/GOOGLE_CALENDAR_SYNC.md) and paste them
/// here. OAuth client ids are identifiers, not secrets, so they are safe to
/// commit.
class GoogleConfig {
  const GoogleConfig._();

  /// The **Web application** OAuth client id. Required on Android (and used
  /// on iOS too). Looks like `1234567890-abc123.apps.googleusercontent.com`.
  static const String serverClientId = '';

  /// The **iOS** OAuth client id. Required on iPhone and iPad. Its reversed
  /// form must also be added as a URL scheme in `ios/Runner/Info.plist`.
  static const String iosClientId = '';
}
