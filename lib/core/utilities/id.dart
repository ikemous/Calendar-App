import 'dart:math';

final Random _random = Random.secure();

/// Random 128-bit hex identifier. Globally unique ids (rather than
/// auto-increment integers) keep records mergeable across devices once cloud
/// sync is added.
String newId() {
  final b = StringBuffer();
  for (var i = 0; i < 16; i++) {
    b.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}
