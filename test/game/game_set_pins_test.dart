// The game set against the monorepo's own packages: no pin lags a local
// checkout. A checkout below its pin is waiting to be released at it (the
// set moves first, in a release round) and is skipped, saying so; one past
// every version its pin allows means the set must move.
//
// The packages are the monorepo's beside this one (`packages/`,
// `plugins/`); in a clone of this repository alone the tests are skipped.

@TestOn('vm')
library;

import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:test/test.dart';

/// The version [name]'s checkout in the monorepo declares, or null when it
/// isn't beside this package.
Version? _localVersion(String name) {
  for (final at in ['../$name', '../../plugins/$name']) {
    final pubspec = File('$at/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final text = pubspec.readAsStringSync();
    if (PubspecFields.name(text) != name) continue;
    return Version.parse(PubspecFields.version(text)!);
  }
  return null;
}

void main() {
  for (final p in GameSet.current.packages) {
    test('${p.name} ${p.constraint} takes its checkout', () {
      final version = _localVersion(p.name);
      if (version == null) {
        markTestSkipped('${p.name} is not in the monorepo');
        return;
      }
      final floor = p.versions.min;
      if (!p.versions.allows(version) && floor != null && version < floor) {
        markTestSkipped(
          '${p.name} $version is not at ${p.constraint} yet: it is released '
          'there this round',
        );
        return;
      }
      expect(
        p.versions.allows(version),
        isTrue,
        reason:
            '${p.name} is $version here, past the ${GameSet.current.id} set: '
            'move its pin in lib/src/game/game_set.dart',
      );
    });
  }

  test("each pin names the version it means: a caret on a release leaves "
      'its prereleases out', () {
    expect(
      VersionConstraint.parse('^0.1.0').allows(Version.parse('0.1.0-dev.3')),
      isFalse,
    );
    expect(
      VersionConstraint.parse(
        '^0.1.0-dev.3',
      ).allows(Version.parse('0.1.0-dev.3')),
      isTrue,
    );
  });
}
