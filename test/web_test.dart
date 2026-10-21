// The primary library's toolkit, on every platform: run on the VM, and in a
// browser with `dart test -p chrome` (JavaScript) and
// `dart test -p chrome -c dart2wasm` (WebAssembly).

import 'dart:convert';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart';
import 'package:test/test.dart';

void main() {
  group('GameSet.bump', () {
    test('moves older constraints to the set, one line each', () {
      const pubspec =
          'name: game\r\n'
          'dependencies:\r\n'
          '  just_game_engine: ^1.6.0 # the engine\r\n'
          '  just_tiled: ^0.4.1\r\n'
          'dev_dependencies:\r\n'
          '  just_game_engine_editor: any\r\n';
      final (next, bumps) = GameSet.current.bump(pubspec);
      final engine = GameSet.current['just_game_engine']!.constraint;
      expect(bumps, {
        'just_game_engine': {'from': '^1.6.0', 'to': engine},
        'just_game_engine_editor': {'from': 'any', 'to': '^0.1.0-dev.1'},
      });
      expect(next, contains('  just_game_engine: $engine # the engine\r\n'));
      expect(next, contains('  just_tiled: ^0.4.1\r\n'));
      expect(GameSet.current.bump(next).$2, isEmpty, reason: 'on the set');
    });

    test('never moves a game ahead of the set back', () {
      const pubspec =
          'dependencies:\n'
          '  just_game_engine: ^2.1.0\n'
          '  just_physics_engine: ^3.0.0\n'
          '  just_tiled: 0.4.1\n'
          '  just_dart: ">=0.2.0 <2.0.0"\n';
      final (next, bumps) = GameSet.current.bump(pubspec);
      expect(bumps, isEmpty);
      expect(next, pubspec);
    });

    test('nor one pub resolved past the set, whatever its constraint', () {
      const pubspec = 'dependencies:\n  just_game_engine: ">=1.6.0"\n';
      expect(GameSet.current.bump(pubspec).$2, hasLength(1));
      final (next, bumps) = GameSet.current.bump(
        pubspec,
        resolved: {'just_game_engine': Version.parse('3.0.0')},
      );
      expect(bumps, isEmpty);
      expect(next, pubspec);
      expect(
        GameSet.current
            .bump(
              pubspec,
              resolved: {'just_game_engine': Version.parse('1.6.1')},
            )
            .$2,
        hasLength(1),
        reason: 'behind the set: moved',
      );
    });
  });

  test("a new game's files: the template filled in, and the first level", () {
    final files = GameTemplate.render(
      GameTemplate.empty,
      names: ProjectNames('rocket_run', title: 'Rocket Run'),
      set: GameSet.current,
      dependencies: const ['  just_game_engine: ^2.0.0'],
      devDependencies: const [],
    );
    expect(files['pubspec.yaml'], contains('  just_game_engine: ^2.0.0'));
    expect(files['lib/main.dart'], contains('Rocket Run'));
    expect(SceneManifest.parse(files[SceneManifest.path]!), ['level_01']);
    expect(files, contains(SceneManifest.scenePath('level_01')));
    expect(
      GameTemplate.withEditorIgnores('build/\n'),
      allOf(contains('.editor_backups/'), contains('.editor_trash/')),
    );
  });

  test("a game's entry points: just.json's, else the defaults", () {
    expect(GameEntries.game(const JustProjectFile()), 'lib/main.dart');
    const file = JustProjectFile(entries: {'editor': 'lib/dev.dart'});
    expect(GameEntries.editor(file), 'lib/dev.dart');
  });

  group('ReleaseRules', () {
    final rules = ReleaseRules.forGame(
      file: const JustProjectFile(title: 'Rocket Run'),
      pubspec: 'hooks:\n  user_defines:\n    just_jolt:\n      build: true\n',
      storeItems: {
        'kit': {
          'editor': {
            'editorOnlyLibraries': ['editor.dart'],
            'modules': [
              {'class': 'KitModule'},
            ],
          },
        },
        'tool': {
          'editor': {
            'editorOnlyLibraries': ['*'],
          },
        },
        // Forbidden already, whole: not listed twice.
        'just_asset_store': {
          'editor': {
            'editorOnlyLibraries': ['*'],
          },
        },
        'just_game_engine_editor': {
          'editor': {
            'editorOnlyLibraries': ['*'],
          },
        },
      },
    );

    test("adds what installed items declare to the editor's own", () {
      expect(rules.forbidden, containsAll(ReleaseRules.coreForbidden));
      expect(rules.forbidden, containsAll(['kit/editor.dart', 'tool/']));
      expect(rules.classNames, contains('KitModule'));
      expect(rules.forbidden.toSet(), hasLength(rules.forbidden.length));
      expect(rules.forbidden, isNot(contains('just_game_engine_editor/')));
      expect(rules.gameMarker, 'Rocket Run');
      expect(rules.buildsJolt, isTrue);
    });

    test('forbids whole packages and named libraries, and nothing else', () {
      expect(
        rules.forbids('package:just_game_engine_editor/editor.dart'),
        isTrue,
      );
      expect(
        rules.forbids('package:just_game_engine_editor_tools/x.dart'),
        isFalse,
        reason: 'another package whose name starts the same',
      );
      expect(rules.forbids('package:kit/editor.dart'), isTrue);
      expect(rules.forbids('package:kit/kit.dart'), isFalse);
      expect(rules.forbids('package:tool/anything.dart'), isTrue);
    });

    test("the marker falls back to the MaterialApp's title", () {
      expect(
        ReleaseRules.gameMarkerIn(
          const JustProjectFile(),
          "MaterialApp(title: 'Old Title')",
        ),
        'Old Title',
      );
      expect(ReleaseRules.gameMarkerIn(const JustProjectFile(), null), isNull);
    });

    test("the store's lockfile lists the items and where they are", () {
      final lock = jsonEncode({
        'items': {
          'kit': {'path': '../kit'},
          'hosted': {'origin': 'store'},
        },
      });
      expect(ReleaseRules.storeItemsIn(lock), {
        'kit': '../kit',
        'hosted': null,
      });
      expect(ReleaseRules.storeItemsIn('{nope'), isEmpty);
    });
  });

  test("an import walk's steps: every Dart file a source names", () {
    const source =
        "import 'dart:io';\n"
        "import 'package:kit/kit.dart';\n"
        "export 'src/a.dart';\n"
        "part 'b.dart';\n"
        "import 'c.dart' if (dart.library.io) 'package:kit/editor.dart';\n"
        "import 'https://example.com/x.dart';\n"
        "final x = [if (a) 'not an import'];\n";
    expect(ReleaseImports.dartUrisIn(source), [
      'package:kit/kit.dart',
      'src/a.dart',
      'b.dart',
      'c.dart',
      'package:kit/editor.dart',
    ]);
  });

  group('ReleaseBuild', () {
    final rules = ReleaseRules.forGame(
      file: const JustProjectFile(title: 'Rocket Run'),
    );

    test('a web build, JavaScript and WebAssembly, holds no editor', () {
      final report = ReleaseBuild.check(
        const ReleaseBuildFiles(
          'web',
          code: {
            'main.dart.js': 'A="Rocket Run"',
            'main.dart.wasm': 'Rocket Run',
          },
        ),
        rules,
      );
      expect(report.ok, isTrue, reason: '${report.errors}');
      expect(report.notes, contains('No editor code in main.dart.wasm.'));
    });

    test("the editor's strings in the WebAssembly fail, naming it", () {
      final report = ReleaseBuild.check(
        const ReleaseBuildFiles(
          'web',
          code: {
            'main.dart.js': '"Rocket Run"',
            'main.dart.wasm': 'Rocket Run Just Runtime Editor',
          },
        ),
        rules,
      );
      expect(report.errors.single, contains('main.dart.wasm'));
      expect(report.errors.single, contains('Just Runtime Editor'));
    });

    test('a title beyond ASCII is found however the compiler wrote it', () {
      final title = ReleaseRules.forGame(
        file: const JustProjectFile(title: 'Café ゲーム'),
      );
      final bs = String.fromCharCode(0x5C);
      for (final code in [
        // As dart2js writes it: every character beyond ASCII escaped.
        '"Caf${bs}xe9 ${bs}u30b2${bs}u30fc${bs}u30e0"',
        latin1.decode(utf8.encode('Café ゲーム')),
      ]) {
        expect(
          ReleaseBuild.check(
            ReleaseBuildFiles('web', code: {'main.dart.js': code}),
            title,
          ).ok,
          isTrue,
          reason: code,
        );
      }
    });

    test('a native build: obfuscation, dev-only plugins, 3D physics', () {
      ReleaseReport check(
        String code, {
        List<String> natives = const [],
      }) => ReleaseBuild.check(
        ReleaseBuildFiles(
          'windows',
          code: {'app.so': code},
          natives: natives,
          nativesPath: 'build/windows/x64/runner/Release',
          pluginList: 'list(APPEND FLUTTER_PLUGIN_LIST\n  editor_plugin\n)\n',
          pluginListPath: 'windows/flutter/generated_plugins.cmake',
          pluginsDependencies: jsonEncode({
            'plugins': {
              'windows': [
                {'name': 'editor_plugin', 'dev_dependency': true},
              ],
            },
          }),
        ),
        ReleaseRules.forGame(file: const JustProjectFile(title: 'Rocket Run')),
      );
      expect(check('Rocket Run').errors.single, contains('obfuscated'));
      expect(
        check('Rocket Run MaterialApp').errors.single,
        contains('editor_plugin, which only a dev dependency brings'),
      );
      expect(
        check(
          'Rocket Run MaterialApp PhysicsSystem3D',
          natives: ['just_jolt.dll'],
        ).errors,
        hasLength(3),
        reason: 'the plugin, the 3D code and the Jolt library',
      );
    });

    test('the plugin lists and the web build config are read', () {
      expect(
        ReleaseBuild.linkedPlugins(
          'list(APPEND FLUTTER_PLUGIN_LIST\n  a\n  b\n)\n'
          'list(APPEND FLUTTER_FFI_PLUGIN_LIST\n  c\n)\n',
        ),
        {'a', 'b', 'c'},
      );
      expect(ReleaseBuild.devOnlyPluginsIn('nope', 'windows'), isEmpty);
      expect(
        ReleaseBuild.wasmIn(
          '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2wasm",'
          '"renderer":"skwasm","mainWasmPath":"main.dart.wasm",'
          '"jsSupportRuntimePath":"main.dart.mjs"},{"compileTarget":'
          '"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"}]};',
        ),
        'main.dart.wasm',
      );
      expect(
        ReleaseBuild.wasmIn(
          '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2js",'
          '"renderer":"canvaskit","mainJsPath":"main.dart.js"}]};',
        ),
        isNull,
      );
    });
  });

  group('FormatsCheck', () {
    test('knows the versioned files by their paths', () {
      expect(FormatsCheck.kindOf('assets/scenes/a.scene.json'), 'scene');
      expect(FormatsCheck.kindOf(TagsFile.path), 'tag library');
      expect(FormatsCheck.kindOf('assets/sprites/a.png'), isNull);
      expect(FormatsCheck.check('assets/sprites/a.json', '{}'), isNull);
    });

    test('tells old, newer, broken and unreadable files apart', () {
      FormatFinding scene(Object? json) =>
          FormatsCheck.check('assets/scenes/a.scene.json', jsonEncode(json))!;
      expect(scene({'version': SceneFormat.current}).old, isFalse);
      expect(scene({'version': 5}).old, isTrue);
      expect(scene({'version': 99}).tooNew, isTrue);
      expect(scene([1]).error, 'not a JSON object');
      expect(
        FormatsCheck.check('assets/scenes/a.scene.json', '{nope')!.error,
        isNotNull,
      );
      final unreadable = FormatsCheck.unreadable(
        'assets/scenes/a.scene.json',
        'Access is denied',
      )!;
      expect(unreadable.error, 'unreadable: Access is denied');
      expect(unreadable.toJson()['kind'], 'scene');
    });

    test('migrates an old scene as the editor writes it', () {
      final out = FormatsCheck.migrated(
        'scene',
        '${jsonEncode({'version': 5, 'name': 'a', 'entities': <Object>[]})}\n',
      );
      expect(
        SceneFormat.versionOf(jsonDecode(out) as Map<String, dynamic>),
        SceneFormat.current,
      );
      expect(out, endsWith('}\n'), reason: 'its final newline kept');
      expect(
        () => FormatsCheck.migrated('tag library', '{}'),
        throwsArgumentError,
      );
    });
  });

  test("the editor's heartbeat goes stale on its own", () {
    final now = DateTime(2026, 10, 13, 12);
    expect(
      EditorPresence.isFresh(
        now.subtract(const Duration(seconds: 3)),
        now: now,
      ),
      isTrue,
    );
    expect(
      EditorPresence.isFresh(now.subtract(EditorPresence.stale), now: now),
      isFalse,
    );
    expect(EditorPresence.path, startsWith(ProjectPaths.workDir));
  });
}
