// `just game doctor`'s SDK floors, engine versions and store links.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:test/test.dart';

import '../support/fake_launcher.dart';

void main() {
  // The engine's constraint in the set: what an upgrade moves it to.
  final engine = GameSet.current['just_game_engine']!.constraint;

  late Directory tmp;
  late GameHarness h;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('just_hooks_');
    h = GameHarness('${tmp.path}/game')..write('pubspec.yaml', 'name: game\n');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('game doctor', () {
    /// A Flutter SDK at [flutter], with Dart [dart].
    void sdk(String flutter, String dart) {
      final root = '${tmp.path}/flutter';
      File(
        '$root/bin/flutter${Platform.isWindows ? '.bat' : ''}',
      ).createSync(recursive: true);
      File('$root/bin/cache/flutter.version.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'frameworkVersion': flutter}));
      File('$root/bin/cache/dart-sdk/version')
        ..createSync(recursive: true)
        ..writeAsStringSync('$dart\n');
      h.env = {'FLUTTER_ROOT': root};
    }

    Future<Map<String, String>> findings() async {
      h.out.clear();
      await h.just(['game', 'doctor', '--json']);
      final list =
          ((jsonDecode('${h.out}') as Map)['result'] as Map)['findings']
              as List;
      return {
        for (final f in list.cast<Map<String, Object?>>())
          '${f['message']}': '${f['severity']}',
      };
    }

    test('Flutter and Dart against the floors the engine needs', () async {
      sdk('3.47.6', '3.12.2');
      final ok = await findings();
      expect(ok['Flutter 3.47.6 (the engine needs >=3.47.1).'], 'ok');
      expect(ok['Dart 3.12.2 (the engine needs ^3.12.2).'], 'ok');
      sdk('3.40.0', '3.11.0');
      final found = await findings();
      expect(
        found['Flutter 3.40.0 is too old: the engine needs >=3.47.1.'],
        'problem',
      );
      expect(
        found['Dart 3.11.0 is too old: the engine needs ^3.12.2.'],
        'problem',
      );
    });

    test("the engine's packages against what pub resolved, and store links "
        'still there', () async {
      final old = package(tmp, 'just_game_engine');
      File(
        '${old.path}/pubspec.yaml',
      ).writeAsStringSync('name: just_game_engine\nversion: 1.6.0\n');
      resolve(Directory(h.project.root), [old]);
      h.write(
        'just_store.lock.json',
        jsonEncode({
          'schema': 1,
          'items': {
            'my_kit': {'origin': 'linked', 'path': '../gone'},
          },
        }),
      );
      var found = await findings();
      expect(
        found['just_game_engine is 1.6.0; the ${GameSet.current.id} game set '
            'has $engine.'],
        'warning',
      );
      expect(found.keys, isNot(contains(contains('newer than'))));
      File(
        '${old.path}/pubspec.yaml',
      ).writeAsStringSync('name: just_game_engine\nversion: 3.0.0\n');
      found = await findings();
      expect(
        found['just_game_engine is 3.0.0, newer than the '
            '${GameSet.current.id} game set ($engine) this just_game_engine_cli '
            'knows.'],
        'warning',
        reason: '`just upgrade` would not move it: a newer plugin would',
      );
      expect(
        found['my_kit is linked to ../gone, which is not there.'],
        'problem',
      );
    });
  });
}
