// The Flutter the engine's games are pinned to: in the pubspec, where
// just_core_cli reads it before this package is fetched, and in GameSet.

@TestOn('vm')
library;

import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:test/test.dart';

void main() {
  test("the pubspec pins the Flutter GameSet pins, inside the set's range", () {
    final pin = PubspecFields.flutterPin(
      File('pubspec.yaml').readAsStringSync(),
    );
    expect(pin, isNotNull, reason: 'pubspec.yaml has no `just: flutter:`');
    expect(pin, GameSet.current.flutterPin);
    expect(
      VersionConstraint.parse(
        GameSet.current.flutter,
      ).allows(Version.parse(pin!)),
      isTrue,
      reason: '${GameSet.current.flutter} must allow the pinned $pin',
    );
  });

  test("a new game's pubspec holds it to the set's Flutter range", () {
    final pubspec = GameTemplate.render(
      GameTemplate.empty,
      names: ProjectNames('my_game'),
      set: GameSet.current,
      dependencies: const [],
      devDependencies: const [],
    )['pubspec.yaml']!;
    expect(
      PubspecConstraints.of(pubspec, 'environment', 'flutter'),
      GameSet.current.flutter,
    );
  });

  test("an upgrade moves the game's Flutter range with the set", () {
    const old =
        'name: game\n'
        'environment:\n'
        '  sdk: ^3.12.2\n'
        '  flutter: ">=3.40.0 <3.41.0"\n';
    final (moved, bumps) = GameSet.current.bump(old);
    expect(
      PubspecConstraints.of(moved, 'environment', 'flutter'),
      GameSet.current.flutter,
    );
    expect(bumps[GameSet.flutterKey], {
      'from': '>=3.40.0 <3.41.0',
      'to': GameSet.current.flutter,
    });
    // A game without the range keeps its pubspec as it is.
    expect(GameSet.current.bump('name: game\n').$2, isEmpty);
  });
}
