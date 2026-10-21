// The hooks `just upgrade`, `just dev link|unlink` and `just doctor` run:
// `game upgrade` (the engine's packages moved, one line each, no pub get),
// `game link` (store items registered, links only they can supply kept),
// and `game doctor`'s SDK floors, engine versions and store links.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_core_cli/project.dart';
import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:test/test.dart';

import 'support/fake_launcher.dart';

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

  group('game upgrade', () {
    const pubspec =
        'name: game\r\n'
        'dependencies:\r\n'
        '  just_game_engine: ^1.6.0 # the engine\r\n'
        '  just_tiled: ^0.4.1\r\n'
        'dev_dependencies:\r\n'
        '  just_asset_store:\r\n'
        '    git:\r\n'
        '      url: https://example.com/store\r\n'
        '  just_game_engine_editor: ^0.0.1\r\n';

    setUp(() => h.write('pubspec.yaml', pubspec));

    test('--check says what would move, and changes nothing', () async {
      expect(
        await h.just(['game', 'upgrade', '--check', '--json']),
        0,
        reason: '${h.err}',
      );
      final result = (jsonDecode('${h.out}') as Map)['result'] as Map;
      expect(result['packages'], {
        'just_game_engine': {'from': '^1.6.0', 'to': engine},
        'just_game_engine_editor': {'from': '^0.0.1', 'to': '^0.1.0-dev.1'},
      });
      expect(result['changed'], isFalse);
      expect(h.read('pubspec.yaml'), pubspec);
    });

    test('moves one line each, never runs pub get, and asks first', () async {
      expect(await h.just(['game', 'upgrade']), 1);
      expect('${h.err}', contains('needs a yes'));
      expect(h.read('pubspec.yaml'), pubspec);

      expect(await h.just(['game', 'upgrade', '--yes']), 0, reason: '${h.err}');
      final next = h.read('pubspec.yaml')!;
      expect(next, contains('  just_game_engine: $engine # the engine\r\n'));
      expect(next, contains('  just_tiled: ^0.4.1\r\n'), reason: 'current');
      expect(
        next,
        contains('      url: https://example.com/store\r\n'),
        reason: 'a block stays as it is',
      );
      expect(next, contains('  just_game_engine_editor: ^0.1.0-dev.1\r\n'));
      expect(h.launcher.runs, isEmpty, reason: '`just upgrade` fetches');

      h.out.clear();
      expect(await h.just(['game', 'upgrade', '--yes']), 0);
      expect(
        '${h.out}',
        contains('needs moving to the ${GameSet.current.id} set'),
      );
    });
  });

  test('game upgrade never moves a package ahead of the set back', () async {
    const ahead =
        'name: game\n'
        'dependencies:\n'
        '  just_game_engine: ^3.0.0\n'
        '  just_physics_engine: ^1.5.0\n';
    h.write('pubspec.yaml', ahead);
    expect(await h.just(['game', 'upgrade', '--yes', '--json']), 0);
    final result = (jsonDecode('${h.out}') as Map)['result'] as Map;
    expect(result['packages'], isEmpty);
    expect(h.read('pubspec.yaml'), ahead);
  });

  group('game link', () {
    late Directory packages;
    late Directory store;
    late Directory editor;
    late Directory engine;

    setUp(() {
      packages = Directory('${tmp.path}/packages')..createSync();
      store = package(
        packages,
        'just_asset_store',
        manifest: {
          'commands': [
            {'name': 'store'},
          ],
        },
        store: const {},
      );
      editor = package(packages, 'just_game_engine_editor', store: const {});
      engine = package(packages, 'just_game_engine');
      h.write(
        'pubspec.yaml',
        'name: game\n'
            'dependencies:\n  just_game_engine: ^2.0.0\n'
            'dev_dependencies:\n  just_game_engine_editor: ^0.1.0-dev.1\n',
      );
      resolve(Directory(h.project.root), [store]);
    });

    List<String> pairs() => [
      for (final d in [store, editor, engine])
        '${d.uri.pathSegments.where((s) => s.isNotEmpty).last}='
            '${normalPath(d.absolute.path)}',
    ];

    test(
      'registers the store items the pubspec lists, through the store',
      () async {
        expect(
          await h.just(['game', 'link', ...pairs()]),
          0,
          reason: '${h.err}',
        );
        final run = h.launcher.runs.single.arguments;
        expect(run.take(4), [
          'run',
          'just_asset_store:just_plugin',
          'store',
          'link',
        ]);
        expect(run.skip(4), [normalPath(editor.absolute.path)]);
      },
    );

    test(
      'a store that may not run, or none, is a word, not a failure',
      () async {
        resolve(
          Directory(h.project.root),
          [store],
          servers: {'just_asset_store': 'https://pub.example.com'},
        );
        expect(await h.just(['game', 'link', '--yes', ...pairs()]), 0);
        expect('${h.err}', contains('were not registered as linked'));
        expect(h.launcher.runs, isEmpty);

        resolve(Directory(h.project.root), const []);
        h.err.clear();
        expect(await h.just(['game', 'link', ...pairs()]), 0);
        expect('${h.err}', contains('no just_asset_store'));
        expect(h.launcher.runs, isEmpty);

        expect(await h.just(['game', 'link', 'nope']), ExitCodes.usage);
      },
    );

    test('--unlink --check refuses while only a link can supply a package '
        'the pubspec asks pub.dev for', () async {
      h.write(
        'pubspec.yaml',
        'name: game\n'
            'dependencies:\n  just_game_engine: ^2.0.0\n'
            'dev_dependencies:\n'
            '  just_asset_store: ^0.1.0\n'
            '  just_game_engine_editor: ^0.1.0-dev.1\n',
      );
      expect(
        await h.just(['game', 'link', '--unlink', '--check', ...pairs()]),
        1,
      );
      // The store comes from pub.dev: only the editor, a store item, is
      // stranded, and the message says how to install it.
      expect('${h.err}', contains('for just_game_engine_editor by version'));
      expect(
        '${h.err}',
        contains('just store install just_game_engine_editor'),
      );
      expect('${h.err}', isNot(contains('null')));
      expect(h.launcher.runs, isEmpty);

      // Only what pub.dev has: the links may go.
      expect(
        await h.just([
          'game',
          'link',
          '--unlink',
          '--check',
          'just_game_engine=${normalPath(engine.absolute.path)}',
        ]),
        0,
      );

      h.write('just_store.lock.json', '{"schema": 1, "items": {}}');
      expect(await h.just(['game', 'link', '--unlink', ...pairs()]), 0);
      expect('${h.out}', contains('store unlink'));
    });
  });

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
