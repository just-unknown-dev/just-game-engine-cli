// `just game link`, the hook `just dev link|unlink` runs: store items
// registered, links only they can supply kept.

@TestOn('vm')
library;

import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:test/test.dart';

import '../support/fake_launcher.dart';

void main() {
  late Directory tmp;
  late GameHarness h;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('just_hooks_');
    h = GameHarness('${tmp.path}/game')..write('pubspec.yaml', 'name: game\n');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

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
            'dependencies:\n'
            '  just_game_engine: ^2.0.0\n'
            '  just_world_builder_kit: ^0.1.0-beta.1\n'
            'dev_dependencies:\n'
            '  just_asset_store: ^0.1.0\n'
            '  just_game_engine_editor: ^0.1.0-dev.1\n',
      );
      final kit = package(packages, 'just_world_builder_kit', store: const {});
      final withKit = [
        ...pairs(),
        'just_world_builder_kit=${normalPath(kit.absolute.path)}',
      ];
      expect(
        await h.just(['game', 'link', '--unlink', '--check', ...withKit]),
        1,
      );
      // The store and the editor come from pub.dev: only the kit, a store
      // item, is stranded, and the message says how to install it.
      expect('${h.err}', contains('for just_world_builder_kit by version'));
      expect('${h.err}', contains('just store install just_world_builder_kit'));
      expect('${h.err}', isNot(contains('just_game_engine_editor')));
      expect('${h.err}', isNot(contains('null')));
      expect(h.launcher.runs, isEmpty);

      // Without the kit, the store and the editor may lose their links.
      expect(
        await h.just(['game', 'link', '--unlink', '--check', ...pairs()]),
        0,
        reason: '${h.err}',
      );

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
}
