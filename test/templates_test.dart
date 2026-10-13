// A new game: the bundled template filled in, and `just game init` — the
// `create` hook `just create` runs — making a fresh Flutter project a game.

@TestOn('vm')
library;

import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart';
import 'package:test/test.dart';

import '../tool/bundle_templates.dart' as tool;
import 'support/fake_launcher.dart';

void main() {
  test('the bundled templates are the files in templates/', () {
    expect(
      File('lib/src/create/templates.g.dart').readAsStringSync(),
      tool.bundle(Directory('templates')),
      reason: 'run `dart run tool/bundle_templates.dart`',
    );
  });

  group('render', () {
    Map<String, String> render(String title) => GameTemplate.render(
      GameTemplate.empty,
      names: ProjectNames('bobs_game', title: title),
      set: GameSet.current,
      dependencies: const ['  just_game_engine: ^2.0.0'],
      devDependencies: const [],
    );

    test('a title is written escaped for each file it goes into', () {
      const title = r'''Bob's "Big" $Game\''';
      final files = render(title);
      expect(
        files['lib/main.dart'],
        contains(
          r'''title: 'Bob\'s "Big" \$Game\\','''
          '\n',
        ),
      );
      expect(
        files['lib/main_editor.dart'],
        contains(r'''title: 'Bob\'s "Big" \$Game\\ — Editor','''),
      );
      expect(
        files['pubspec.yaml'],
        contains(r'''description: "Bob's \"Big\" $Game\\, made with'''),
      );
    });

    test('a pubspec with the lines given, and a first level', () {
      final files = render('Bob');
      final pubspec = files['pubspec.yaml']!;
      expect(pubspec, contains('name: bobs_game\n'));
      expect(pubspec, contains('  sdk: ${GameSet.current.dart}\n'));
      expect(
        pubspec,
        contains('    sdk: flutter\n  just_game_engine: ^2.0.0\n'),
      );
      expect(pubspec, isNot(contains('{{')));
      expect(files['lib/main.dart'], contains('class BobsGameApp'));
      expect(
        files[SceneManifest.scenePath('level_01')],
        SceneStarters.encode(SceneStarters.twoD('level_01')),
      );
      expect(SceneManifest.parse(files[SceneManifest.path]!), ['level_01']);
      expect(files.keys, isNot(contains('just.json')), reason: "just create's");
      for (final e in files.entries) {
        expect(e.key, isNot(endsWith('.tmpl')));
        expect(e.value, isNot(contains('{{')), reason: e.key);
      }
    });

    test('a template it does not have, or a broken title, is refused', () {
      expect(
        () => GameTemplate.render(
          'nope',
          names: ProjectNames('x'),
          set: GameSet.current,
          dependencies: const [],
          devDependencies: const [],
        ),
        throwsArgumentError,
      );
      expect(() => render('Tab\there'), throwsArgumentError);
    });

    test("the direct packages are in the sets: the engine's in the game "
        "set, the tools in just_core_cli's tool set", () {
      final direct = GameTemplate.direct(GameSet.current, ToolSet.current);
      expect(direct.map((p) => p.name), GameTemplate.directPackages);
      expect([
        for (final p in direct)
          if (p.dev) p.name,
      ], containsAll(['just_core_cli', 'just_game_engine_cli']));
      for (final tool in ['just_core_cli', 'just_game_engine_cli']) {
        expect(GameSet.current[tool], isNull, reason: "the tool set's");
      }
      expect(
        () => GameTemplate.direct(
          const GameSet(id: 'x', flutter: 'any', dart: 'any', packages: []),
          ToolSet.current,
        ),
        throwsStateError,
      );
    });

    test("the store's repository is its website: the package is in a "
        'folder', () {
      final store = GameSet.current['just_asset_store']!;
      expect(store.source, PackageSource.git);
      expect(
        TemplateRenderer.dependencyLines(store),
        contains('      path: packages/just_asset_store'),
      );
      expect(GameSet.named(GameSet.current.id), same(GameSet.current));
    });

    test('the editor ignores and the entitlement are added once', () {
      final ignores = GameTemplate.withEditorIgnores('build/\n');
      expect(ignores, contains('.editor_trash/\n'));
      expect(GameTemplate.withEditorIgnores(ignores), ignores);
      const plist = '<plist>\r\n<dict>\r\n</dict>\r\n</plist>\r\n';
      final allowed = GameTemplate.withNetworkClient(plist);
      expect(allowed, contains('com.apple.security.network.client'));
      expect(allowed.replaceAll('\r\n', '').contains('\n'), isFalse);
      expect(GameTemplate.withNetworkClient(allowed), allowed);
    });
  });

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
        ('just_asset_store_editor', true),
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
        'just_asset_store_editor',
        'just_game_engine_editor',
      ], reason: 'only the dev store items are registered');
      expect(h.launcher.runs, hasLength(2));

      final pubspec = h.read('pubspec.yaml')!;
      expect(pubspec, contains('name: space_game'));
      expect(pubspec, contains('  just_game_engine: ^2.0.0'));
      expect(pubspec, contains('  just_game_engine_editor: ^0.1.0'));
      expect(pubspec, contains('  just_core_cli: ^0.1.0'));
      expect(pubspec, contains('  just_game_engine_cli: ^0.1.0'));
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

    test('from the store: the editor installed, a store template laid over, '
        'and Flutter GPU on for a 3D game', () async {
      h.launcher.exitCodeFor = (args) {
        if (args.contains('template')) {
          // The template brings a game that draws in 3D.
          h.write(
            'lib/game/boot3d.dart',
            'const c = EngineConfig(graphics3D: Graphics3D());',
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
        'run just_asset_store:just_plugin store install '
            'just_game_engine_editor --yes',
        'run just_asset_store:just_plugin store install '
            'just_asset_store_editor --yes',
        'run just_asset_store:just_plugin store template studio_kit '
            '--overwrite --yes --source a',
      ]);
      final pubspec = h.read('pubspec.yaml')!;
      expect(pubspec, contains('    git:\n'));
      expect(pubspec, contains('      path: packages/just_asset_store\n'));
      expect(
        pubspec,
        isNot(contains('just_game_engine_editor')),
        reason: 'the store adds it',
      );
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

    test('a store from a package mirror runs only once allowed', () async {
      h.launcher.servers = {'just_asset_store': 'https://pub.example.com'};
      expect(await h.just(['game', 'init', '--yes']), 1);
      expect('${h.err}', contains('just_asset_store is not allowed to run'));
      expect('${h.err}', contains('--yes never allows a plugin'));
      expect(ran(), ['pub get'], reason: 'the store never ran');

      // Allowed in just.json, as any plugin can be (or asked in a terminal).
      h.project.writeProjectFile(
        h.project.readProjectFile().allowing('just_asset_store'),
      );
      h.launcher.runs.clear();
      expect(await h.just(['game', 'init', '--yes']), 0, reason: '${h.err}');
      expect(ran().last, contains('store install just_asset_store_editor'));
    });

    test('a store that is not there, or a failing step, fails it; the '
        'engine set is its own', () async {
      expect(
        await h.just(['game', 'init', '--set', '2026.10', '--yes']),
        ExitCodes.usage,
        reason: '`just create` no longer passes a set',
      );

      h.launcher.packages = const [];
      expect(await h.just(['game', 'init', '--yes']), 1);
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

  test("the manifest's hooks are commands the plugin has", () async {
    final manifest = PluginManifest.parse(
      File('just_plugin.json').readAsStringSync(),
    );
    expect(manifest.commands.keys, ['game']);
    final game = GameCommand();
    for (final hook in [
      'create',
      'doctor',
      'check',
      'upgrade',
      'migrate',
      'link',
    ]) {
      final words = manifest.hooks[hook]!.split(' ');
      expect(words.first, 'game', reason: hook);
      expect(game.subcommands.keys, contains(words[1]), reason: hook);
    }
  });
}
