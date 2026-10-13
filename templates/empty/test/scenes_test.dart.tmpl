// The levels the game ships: listed, current, and loadable.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

void main() {
  test('every listed scene exists and needs no newer engine', () {
    final names = SceneManifest.parse(
      File(SceneManifest.path).readAsStringSync(),
    );
    expect(names, isNotEmpty, reason: 'the game starts on the first one');
    for (final name in names) {
      final file = File(SceneManifest.scenePath(name));
      expect(file.existsSync(), isTrue, reason: '$name is listed');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(() => SceneFormat.migrate(json), returnsNormally);
    }
  });
}
