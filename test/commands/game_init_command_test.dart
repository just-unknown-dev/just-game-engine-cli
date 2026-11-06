// `just game init`, the `create` hook `just create` runs: a fresh
// Flutter project made a game.

@TestOn('vm')
library;

import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart';
import 'package:test/test.dart';

import '../support/fake_launcher.dart';

void main() {
  group('init', () {
    late Directory tmp;
    late Directory packages;
    late GameHarness h;
    const storeManifest = {
      'commands': [
        {'name': 'store'},
      ],
    };

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('just_init_');
      File(
        '${tmp.path}/flutter/bin/flutter${Platform.isWindows ? '.bat' : ''}',
      ).createSync(recursive: true);
      packages = Directory('${tmp.path}/packages')..createSync();
      for (final (name, item) in [
        ('just_core_cli', false),
        ('just_game_engine_cli', false),
        ('just_game_engine', false),
        ('just_game_engine_editor', true),
      ]) {
        package(packages, name, store: item ? const {} : null);
      }
      final store = package(
        packages,
        'just_asset_store',
        manifest: storeManifest,
        store: const {},
      );
      // What `just create` leaves: flutter create's files, just.json, and
      // the packages fetched.
      h =
          GameHarness(
              '${tmp.path}/space_game',
              launcher: FakeLauncher(packages: [store]),
            )
            ..env = {'FLUTTER_ROOT': '${tmp.path}/flutter'}
            ..write('pubspec.yaml', 'name: space_game\n')
            ..write('.gitignore', 'build/\n')
            ..write('test/widget_test.dart', '// MyApp')
            ..write(
              GameTemplate.debugEntitlements,
              '<plist>\n<dict>\n</dict>\n</plist>\n',
            )
            ..write(
              'windows/runner/main.cpp',
              File('test/fixtures/runners/windows_main.cpp').readAsStringSync(),
            );
      h.project.writeProjectFile(
        JustProjectFile(title: 'Space Game', set: ToolSet.current.id),
      );
      resolve(Directory(h.project.root), [store]);
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    List<String> ran() => [for (final r in h.launcher.runs) '$r'];

    test('--local more than once: the store items of each folder are '
        'linked; a package in two of them stops it first', () async {
      // A second folder beside packages/, holding one of the set's store
      // items (the editor), so each folder has one to link.
      final plugins = Directory('${tmp.path}/plugins')..createSync();
      Directory(
        '${packages.path}/just_game_engine_editor',
      ).deleteSync(recursive: true);
      package(plugins, 'just_game_engine_editor', store: const {});
      expect(
        await h.just([
          'game',
          'init',
          '--local',
          packages.path,
          '--local',
          plugins.path,
          '--yes',
        ]),
        0,
        reason: '${h.err}',
      );
      expect(
        h.launcher.runs.last.arguments.skip(4).map((p) => p.split('/').last),
        ['just_asset_store', 'just_game_engine_editor'],
      );

      package(plugins, 'just_game_engine');
      h.launcher.runs.clear();
      expect(
        await h.just([
          'game',
          'init',
          '--local',
          packages.path,
          '--local',
          plugins.path,
          '--yes',
        ]),
        1,
      );
      expect(
        '${h.err}',
        contains('just_game_engine is checked out in more than one folder'),
      );
      expect(h.launcher.runs, isEmpty, reason: 'nothing ran');
    });

    test('--local: the game template, and the editor linked', () async {
      expect(
        await h.just(['game', 'init', '--local', packages.path, '--yes']),
        0,
        reason: '${h.err}',
      );
      expect(h.launcher.runs.first.arguments, ['pub', 'get']);
      final link = h.launcher.runs.last.arguments;
      expect(link.take(4), [
        'run',
        'just_asset_store:just_plugin',
        'store',
        'link',
      ]);
      expect(link.skip(4).map((p) => p.split('/').last), [
        'just_asset_store',
        'just_game_engine_editor',
      ], reason: 'only the dev store items are registered');
      expect(h.launcher.runs, hasLength(2));

      final pubspec = h.read('pubspec.yaml')!;
      expect(pubspec, contains('name: space_game'));
      expect(pubspec, contains('  just_game_engine: ^2.0.0'));
      expect(
        pubspec,
        contains(
          '  just_game_engine_editor: '
          '${GameSet.current['just_game_engine_editor']!.constraint}',
        ),
      );
      // The tools as just_core_cli's ToolSet.current (2026.11) names them.
      expect(pubspec, contains('  just_core_cli: ^0.2.0'));
      expect(pubspec, contains('  just_game_engine_cli: ^0.2.0'));
      expect(pubspec, isNot(contains('{{')));
      expect(h.read('lib/main.dart'), contains('class SpaceGameApp'));
      expect(h.read('lib/main.dart'), contains("title: 'Space Game'"));
      expect(SceneManifest.parse(h.read(SceneManifest.path)!), ['level_01']);
      expect(h.read('test/widget_test.dart'), isNull);
      expect(h.read('.gitignore'), contains('.editor_backups/'));
      expect(h.read('.gitignore'), contains('pubspec_overrides.yaml'));
      expect(
        h.read(GameTemplate.debugEntitlements),
        contains('com.apple.security.network.client'),
      );
      expect(
        h.read('windows/runner/main.cpp'),
        isNot(contains('set_enable_flutter_gpu')),
        reason: 'a 2D game',
      );
      expect('${h.out}', contains('`just game run --editor`'));
    });

    test('from pub.dev: the editor in the pubspec, a store template laid '
        'over, and Flutter GPU on for a 3D game', () async {
      h.launcher.exitCodeFor = (args) {
        if (args.contains('template')) {
          // The template brings a game that draws in 3D.
          h.write(
            'lib/game/boot3d.dart',
            'const c = EngineConfig(services: [Graphics3D()]);',
          );
        }
        return 0;
      };
      expect(
        await h.just([
          'game',
          'init',
          '--title',
          'Space Game',
          '--template',
          'studio_kit',
          '--source',
          'a',
          '--yes',
        ]),
        0,
        reason: '${h.err}',
      );
      expect(ran(), [
        'pub get',
        'run just_asset_store:just_plugin store template studio_kit '
            '--overwrite --yes --source a',
      ], reason: 'the store installs nothing: the editor is on pub.dev');
      final pubspec = h.read('pubspec.yaml')!;
      for (final name in ['just_asset_store', 'just_game_engine_editor']) {
        expect(
          pubspec.split('dev_dependencies:').last,
          contains('  $name: ${GameSet.current[name]!.constraint}\n'),
          reason: '$name: from pub.dev, a dev dependency',
        );
      }
      expect(
        h.read('windows/runner/main.cpp'),
        contains('project.set_enable_flutter_gpu(true);'),
      );
    });

    test('the tools stay in the pubspec on one line each, for `just upgrade` '
        'to move', () async {
      for (final local in [true, false]) {
        expect(
          await h.just([
            'game',
            'init',
            if (local) ...['--local', packages.path],
            '--yes',
          ]),
          0,
          reason: '${h.err}',
        );
        final pubspec = h.read('pubspec.yaml')!;
        for (final tool in ['just_core_cli', 'just_game_engine_cli']) {
          expect(
            PubspecConstraints.of(pubspec, 'dev_dependencies', tool),
            ToolSet.current[tool]!.constraint,
            reason: '$tool (local: $local)',
          );
        }
      }
    });

    test('a title is written escaped, as `just create` passes it', () async {
      const title = r'''Bob's "Big" $Game\ & <Co>''';
      expect(
        await h.just(['game', 'init', '--title', title, '--yes']),
        0,
        reason: '${h.err}',
      );
      expect(
        h.read('lib/main.dart'),
        contains(r'''title: 'Bob\'s "Big" \$Game\\ & <Co>','''),
      );
      expect(
        h.read('pubspec.yaml'),
        contains(r'''description: "Bob's \"Big\" $Game\\ & <Co>, made'''),
      );
    });

    test('the empty game needs no store: everything is on pub.dev', () async {
      expect(await h.just(['game', 'init', '--yes']), 0, reason: '${h.err}');
      expect(ran(), ['pub get'], reason: 'the store never ran');
      expect(
        PubspecConstraints.of(
          h.read('pubspec.yaml')!,
          'dev_dependencies',
          'just_game_engine_editor',
        ),
        GameSet.current['just_game_engine_editor']!.constraint,
      );
    });

    test('a store from pub.dev runs; from a package mirror only once '
        'allowed', () async {
      const init = ['game', 'init', '--template', 'studio_kit', '--yes'];
      // Where the game set gets it: the ecosystem's own there.
      h.launcher.servers = {'just_asset_store': 'https://pub.dev'};
      expect(await h.just(init), 0, reason: '${h.err}');
      expect(ran().last, contains('store template studio_kit'));

      h.launcher
        ..runs.clear()
        ..servers = {'just_asset_store': 'https://pub.example.com'};
      expect(await h.just(init), 1);
      expect('${h.err}', contains('just_asset_store is not allowed to run'));
      expect('${h.err}', contains('--yes never allows a plugin'));
      expect(ran(), ['pub get'], reason: 'the store never ran');

      // Allowed in just.json, as any plugin can be (or asked in a terminal).
      h.project.writeProjectFile(
        h.project.readProjectFile().allowing('just_asset_store'),
      );
      h.launcher.runs.clear();
      expect(await h.just(init), 0, reason: '${h.err}');
      expect(ran().last, contains('store template studio_kit'));
    });

    test('a store that is not there, or a failing step, fails it; the '
        'engine set is its own', () async {
      expect(
        await h.just(['game', 'init', '--set', '2026.10', '--yes']),
        ExitCodes.usage,
        reason: '`just create` no longer passes a set',
      );

      h.launcher.packages = const [];
      expect(
        await h.just(['game', 'init', '--template', 'studio_kit', '--yes']),
        1,
      );
      expect('${h.err}', contains('no just_asset_store'));

      h.launcher.exitCodeFor = (args) => args.first == 'pub' ? 1 : 0;
      expect(await h.just(['game', 'init', '--yes']), 1);
      expect('${h.err}', contains('flutter pub get failed'));
    });

    test('is hidden: `just create` is how a game starts', () async {
      expect(await h.just(['game', '--help']), 0);
      expect('${h.out}', isNot(contains('init')));
      expect('${h.out}', contains('migrate'));
    });
  });
}
