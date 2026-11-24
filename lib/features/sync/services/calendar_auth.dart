import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../app/config/google_config.dart';

/// Thrown when sign-in fails for a reason worth showing to the user.
class CalendarAuthException implements Exception {
  const CalendarAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Sign-in and access tokens for the cloud calendar. Behind an interface so
/// sync can be tested without Google.
abstract interface class CalendarAuth {
  /// Whether the app has been given the client ids it needs.
  bool get isConfigured;

  /// Shows the account chooser and asks for calendar access. Returns the
  /// account's email, or null if the user cancelled.
  Future<String?> signIn();

  /// A valid access token, or null if the user must sign in again. Never
  /// shows UI.
  Future<String?> accessToken();

  Future<void> signOut();
}

/// [CalendarAuth] backed by Google Sign-In.
class GoogleCalendarAuth implements CalendarAuth {
  /// Read and write events only: no access to other Google data.
  static const scopes = ['https://www.googleapis.com/auth/calendar.events'];

  bool _initialized = false;
  GoogleSignInAccount? _account;

  bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  bool get isConfigured => _isIos
      ? GoogleConfig.iosClientId.isNotEmpty
      : GoogleConfig.serverClientId.isNotEmpty;

  Future<void> _init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      clientId: _isIos ? GoogleConfig.iosClientId : null,
      serverClientId: GoogleConfig.serverClientId.isEmpty
          ? null
          : GoogleConfig.serverClientId,
    );
    _initialized = true;
  }

  @override
  Future<String?> signIn() async {
    if (!isConfigured) {
      throw const CalendarAuthException(
          'Google sync has not been set up for this build.');
    }
    try {
      await _init();
      final account =
          await GoogleSignIn.instance.authenticate(scopeHint: scopes);
      _account = account;
      // Ask for calendar access if sign-in alone did not grant it.
      final client = account.authorizationClient;
      if (await client.authorizationForScopes(scopes) == null) {
        await client.authorizeScopes(scopes);
      }
      return account.email;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw CalendarAuthException(switch (e.code) {
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          'Google sign-in is not configured correctly for this app.',
        _ => 'Could not sign in to Google. Please try again.',
      });
    }
  }

  @override
  Future<String?> accessToken() async {
    if (!isConfigured) return null;
    try {
      await _init();
      _account ??=
          await GoogleSignIn.instance.attemptLightweightAuthentication();
      final client = _account?.authorizationClient ??
          GoogleSignIn.instance.authorizationClient;
      return (await client.authorizationForScopes(scopes))?.accessToken;
    } on GoogleSignInException {
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    if (!isConfigured) return;
    try {
      await _init();
      await GoogleSignIn.instance.signOut();
    } on GoogleSignInException {
      // Signing out locally is all that matters here.
    }
    _account = null;
  }
}
