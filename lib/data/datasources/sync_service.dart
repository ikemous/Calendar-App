/// The hook data notifiers call after every local write, so a cloud sync can
/// react. Local storage never depends on it.
///
/// The app's implementation is Google Calendar sync (see
/// `features/sync/providers/sync_controller.dart`), which is idle until the
/// user connects an account.
abstract interface class SyncService {
  /// Whether the user has opted in to syncing. Nothing leaves the device
  /// while this is false.
  bool get isEnabled;

  Future<void> recordChanged(String collection, String id);
  Future<void> recordDeleted(String collection, String id);
  Future<void> syncNow();
}

/// A do-nothing implementation, for code that must run with sync absent.
class LocalOnlySyncService implements SyncService {
  const LocalOnlySyncService();

  @override
  bool get isEnabled => false;

  @override
  Future<void> recordChanged(String collection, String id) async {}

  @override
  Future<void> recordDeleted(String collection, String id) async {}

  @override
  Future<void> syncNow() async {}
}
