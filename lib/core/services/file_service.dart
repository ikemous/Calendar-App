import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show Rect;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// File hand-off to and from the rest of the device. Kept behind an
/// interface so screens can be tested without platform channels.
abstract interface class FileService {
  /// Lets the user choose where to save the file. Returns false if they
  /// cancelled.
  Future<bool> saveToDevice(String fileName, String content, String mimeType);

  /// Opens the system share sheet with the file attached.
  Future<void> share(String fileName, String content, String mimeType,
      {Rect? origin});

  /// Lets the user pick a file and returns its text, or null if cancelled.
  Future<String?> pickTextFile();

  /// Lets the user pick a picture for the lock screen. A small copy is kept
  /// in the app's private storage and its path returned; null if cancelled.
  /// Throws a [FormatException] if the file is not a picture.
  Future<String?> pickLockScreenImage();

  /// Deletes a file previously returned by [pickLockScreenImage].
  Future<void> deleteLockScreenImage(String path);
}

class PlatformFileService implements FileService {
  const PlatformFileService();

  @override
  Future<bool> saveToDevice(
      String fileName, String content, String mimeType) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: utf8.encode(content),
      mimeType: mimeType,
    );
    return uri != null;
  }

  @override
  Future<void> share(String fileName, String content, String mimeType,
      {Rect? origin}) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(content, flush: true);
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: mimeType, name: fileName)],
        sharePositionOrigin: origin,
      ));
    } finally {
      // Don't leave a copy of private calendar data in the cache.
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<String?> pickTextFile() async {
    final picked = await FilePicker.pickFile();
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<String?> pickLockScreenImage() async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null) return null;
    final ui.Image image;
    try {
      final codec = await ui.instantiateImageCodec(
        await picked.readAsBytes(),
        targetWidth: lockScreenImageWidth,
      );
      image = (await codec.getNextFrame()).image;
    } catch (_) {
      throw const FormatException('Not a picture');
    }
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png == null) throw const FormatException('Not a picture');
    final dir = await getApplicationSupportDirectory();
    // A new name each time, so nothing keeps showing a cached old picture.
    final file = File(p.join(dir.path,
        'lock_screen_${DateTime.now().millisecondsSinceEpoch}.png'));
    await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
    return file.path;
  }

  @override
  Future<void> deleteLockScreenImage(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

/// Width of the stored lock screen picture. It is shown as a small
/// thumbnail, and notifications may only carry small bitmaps.
const int lockScreenImageWidth = 256;

final fileServiceProvider =
    Provider<FileService>((ref) => const PlatformFileService());
