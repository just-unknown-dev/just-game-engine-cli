// Proving the editor never ships: the rules a project's installed items
// declare, the import walk, a build's contents, and the saved formats.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late JustProject project;

  void write(String path, String text) => File('${tmp.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('just_release_');
    project = JustProject('${tmp.path}/game');
    write('game/pubspec.yaml', 'name: game\n');
    write('game/just.json', jsonEncode({'title': 'Rocket Run'}));
    // Packages: the editor, and a kit whose editor half is a library.
    write(
      'editor/lib/just_game_engine_editor.dart',
      'class JustGameEditorPlugin {}',
    );
    write('kit/lib/kit.dart', "export 'src/runtime.dart';");
    write('kit/lib/src/runtime.dart', 'class Runtime {}');
    write('kit/lib/editor.dart', 'class KitModule {}');
    write(
      'kit/just_store.json',
      jsonEncode({
        'editor': {
          'editorOnlyLibraries': ['editor.dart'],
          'modules': [
            {'class': 'KitModule', 'library': 'package:kit/editor.dart'},
          ],
        },
      }),
    );
    write(
      'game/just_store.lock.json',
      jsonEncode({
        'schema': 1,
        'items': {
          'kit': {'origin': 'linked', 'path': '../kit', 'kind': 'kit'},
        },
      }),
    );
    write(
      'game/.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          for (final (name, dir) in [
            ('just_game_engine_editor', 'editor'),
            ('kit', 'kit'),
            ('game', 'game'),
          ])
            {
              'name': name,
              'rootUri': Directory('${tmp.path}/$dir').absolute.uri.toString(),
              'packageUri': 'lib/',
            },
        ],
      }),
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('ReleaseRules', () {
    test("adds what installed items declare to the editor's own", () {
      final rules = project.releaseRules();
      expect(rules.forbidden, containsAll(ReleaseRules.coreForbidden));
      expect(rules.forbidden, contains('kit/editor.dart'));
      expect(rules.classNames, contains('KitModule'));
      expect(rules.gameMarker, 'Rocket Run');
    });

    test('the tools are editor-only: just and these commands', () {
      expect(
        ReleaseRules.coreForbidden,
        containsAll(['just_core_cli/', 'just_game_engine_cli/']),
      );
    });

    test("without just.json, the game's MaterialApp title is the marker", () {
      File('${project.root}/just.json').deleteSync();
      write('game/lib/main.dart', "MaterialApp(title: 'Old Title')");
      expect(project.releaseRules().gameMarker, 'Old Title');
    });
  });

  group('ReleaseImports', () {
    test('a clean game passes; the kit runtime may ship', () {
      write('game/lib/main.dart', "import 'package:kit/kit.dart';");
      expect(project.editorReachableFrom('lib/main.dart'), isEmpty);
    });

    test('finds the editor however it is reached, and says how', () {
      write('game/lib/main.dart', "import 'game/boot.dart';");
      write(
        'game/lib/game/boot.dart',
        "import 'package:kit/editor.dart';\n"
            "import '../editor/wiring.dart';\n"
            "final x = [if (a) 'hinttext: not an import'];",
      );
      write('game/lib/editor/wiring.dart', '');
      expect(project.editorReachableFrom('lib/main.dart'), [
        'lib/main.dart -> game/boot.dart -> package:kit/editor.dart',
        'lib/main.dart -> game/boot.dart -> ../editor/wiring.dart',
      ]);
    });

    test("a game file whose name starts with editor isn't lib/editor/", () {
      write(
        'game/lib/main.dart',
        "import 'editor_theme.dart';\nimport 'editors/list.dart';",
      );
      write('game/lib/editor_theme.dart', '');
      write('game/lib/editors/list.dart', '');
      expect(project.editorReachableFrom('lib/main.dart'), isEmpty);
    });

    test(
      'where case counts, two files that differ only in it are both walked',
      () {
        write('game/lib/main.dart', "import 'foo.dart';\nimport 'Foo.dart';");
        write('game/lib/foo.dart', '');
        write('game/lib/Foo.dart', "import 'package:kit/editor.dart';");
        expect(project.editorReachableFrom('lib/main.dart'), [
          'lib/main.dart -> Foo.dart -> package:kit/editor.dart',
        ]);
      },
      skip: Platform.isLinux ? false : 'a case-sensitive disk',
    );

    test('follows conditional imports too', () {
      write(
        'game/lib/main.dart',
        "import 'a.dart' if (dart.library.io) "
            "'package:just_game_engine_editor/just_game_engine_editor.dart';",
      );
      write('game/lib/a.dart', '');
      expect(project.editorReachableFrom('lib/main.dart'), hasLength(1));
    });
  });

  group('ReleaseBuild', () {
    void web(String code) => write('game/build/web/main.dart.js', code);

    test('a build without the editor passes', () {
      web('"Rocket Run" MaterialApp');
      expect(project.checkReleaseBuild('web').ok, isTrue);
    });

    test("a build with the editor's strings fails, naming them", () {
      web('"Rocket Run" "Just Runtime Editor"');
      final report = project.checkReleaseBuild('web');
      expect(report.ok, isFalse);
      expect(report.errors.single, contains('Just Runtime Editor'));
    });

    test("another game's build, an obfuscated one and none are refused", () {
      web('"Other Game"');
      expect(
        project.checkReleaseBuild('web').errors.single,
        contains('Rocket Run'),
      );
      write(
        'game/build/windows/x64/runner/Release/data/app.so',
        'Rocket Run xQ3',
      );
      expect(
        project.checkReleaseBuild('windows').errors.single,
        contains('obfuscated'),
      );
      expect(
        project.checkReleaseBuild('linux').errors.single,
        contains('No release build'),
      );
    });

    test('a title beyond ASCII is found however the compiler wrote it', () {
      void title(String t) => write('game/just.json', jsonEncode({'title': t}));
      // dart2js escapes everything beyond ASCII.
      title('Café Quest');
      web(r'A="Caf\xe9 Quest" MaterialApp');
      expect(project.checkReleaseBuild('web').ok, isTrue);
      title('ゲーム');
      web(r'A="ゲーム"');
      expect(project.checkReleaseBuild('web').ok, isTrue);
      title('Bob\'s "Big" Game');
      web(r'''A="Bob's \"Big\" Game"''');
      expect(project.checkReleaseBuild('web').ok, isTrue);
      // An AOT snapshot keeps Latin-1 as bytes, the rest as UTF-16LE.
      final aot = File(
        '${tmp.path}/game/build/windows/x64/runner/Release/data/app.so',
      )..createSync(recursive: true);
      title('ゲーム');
      aot.writeAsBytesSync([
        ...latin1.encode('MaterialApp '),
        for (final u in 'ゲーム'.codeUnits) ...[u & 0xFF, u >> 8],
      ]);
      expect(project.checkReleaseBuild('windows').ok, isTrue);
      title('Café');
      aot.writeAsBytesSync(latin1.encode('MaterialApp Café'));
      expect(project.checkReleaseBuild('windows').ok, isTrue);
      title('Another');
      expect(project.checkReleaseBuild('windows').ok, isFalse);
    });

    test("a --wasm build's WebAssembly is checked too; a stale one isn't", () {
      web('"Rocket Run" MaterialApp');
      write('game/build/web/main.dart.wasm', 'Rocket Run Just Runtime Editor');
      // Without flutter_bootstrap.js, the WebAssembly beside it counts.
      expect(
        project.checkReleaseBuild('web').errors.single,
        allOf(contains('main.dart.wasm'), contains('Just Runtime Editor')),
      );
      write(
        'game/build/web/flutter_bootstrap.js',
        '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2wasm",'
            '"renderer":"skwasm","mainWasmPath":"main.dart.wasm"},'
            '{"compileTarget":"dart2js","renderer":"canvaskit",'
            '"mainJsPath":"main.dart.js"}]};',
      );
      expect(project.checkReleaseBuild('web').ok, isFalse);
      write(
        'game/build/web/flutter_bootstrap.js',
        '_flutter.buildConfig = {"builds":[{"compileTarget":"dart2js",'
            '"renderer":"canvaskit","mainJsPath":"main.dart.js"}]};',
      );
      final report = project.checkReleaseBuild('web');
      expect(report.ok, isTrue, reason: 'this build loads no WebAssembly');
      expect(report.warnings.single, contains('older --wasm build'));
    });

    test('a Windows build is found for its architecture', () {
      write(
        'game/build/windows/arm64/runner/Release/data/app.so',
        'Rocket Run MaterialApp',
      );
      expect(project.checkReleaseBuild('windows').ok, isTrue);
    });

    test('class names count in a native build, from installed modules too', () {
      write(
        'game/build/windows/x64/runner/Release/data/app.so',
        'Rocket Run MaterialApp KitModule',
      );
      expect(
        project.checkReleaseBuild('windows').errors.single,
        contains('KitModule'),
      );
    });
  });

  group('3D physics', () {
    const release = 'game/build/windows/x64/runner/Release';
    const jolt = 'hooks:\n  user_defines:\n    just_jolt:\n      build: true\n';

    test('the pubspec switch is read, and only that one', () {
      expect(ReleaseRules.buildsJoltIn('name: game\n$jolt'), isTrue);
      expect(ReleaseRules.buildsJoltIn('name: game\n'), isFalse);
      expect(
        ReleaseRules.buildsJoltIn(jolt.replaceFirst('true', 'false')),
        isFalse,
      );
      expect(
        ReleaseRules.buildsJoltIn(jolt.replaceFirst('just_jolt', 'just_other')),
        isFalse,
      );
      expect(
        ReleaseRules.buildsJoltIn(
          'hooks:\n  user_defines:\n    just_jolt:\n      dev: true\n',
        ),
        isFalse,
      );
      expect(
        ReleaseRules.buildsJoltIn(
          'hooks: # native builds\n  user_defines:\n    just_jolt:\n      build: true # 3D\n',
        ),
        isTrue,
      );
      expect(project.releaseRules().buildsJolt, isFalse);
    });

    test('a 2D game whose build holds none of it passes, and says so', () {
      write('$release/data/app.so', 'Rocket Run MaterialApp');
      final report = project.checkReleaseBuild('windows');
      expect(report.ok, isTrue);
      expect(report.notes, contains(contains('No 3D physics')));
    });

    test("3D physics' code in a 2D game's build fails, naming it", () {
      write('$release/data/app.so', 'Rocket Run MaterialApp PhysicsSystem3D');
      expect(
        project.checkReleaseBuild('windows').errors.single,
        contains('PhysicsSystem3D'),
      );
      write(
        'game/build/web/main.dart.js',
        '"Rocket Run" "rigid_body_3d_d3ff8994"',
      );
      expect(
        project.checkReleaseBuild('web').errors.single,
        contains('rigid_body_3d_d3ff8994'),
      );
    });

    test("Jolt's library in a 2D game's build fails", () {
      write('$release/data/app.so', 'Rocket Run MaterialApp');
      write('$release/just_jolt.dll', '');
      expect(
        project.checkReleaseBuild('windows').errors.single,
        contains('just_jolt.dll'),
      );
    });

    test('a 3D game may hold both', () {
      write('game/pubspec.yaml', 'name: game\n$jolt');
      write('$release/data/app.so', 'Rocket Run MaterialApp PhysicsSystem3D');
      write('$release/just_jolt.dll', '');
      final report = project.checkReleaseBuild('windows');
      expect(report.ok, isTrue);
      expect(report.notes, contains(contains('just_jolt.dll')));
    });
  });

  test('FormatsCheck tells old, newer and broken files apart', () {
    write(
      'game/assets/scenes/now.scene.json',
      jsonEncode({'version': SceneFormat.current}),
    );
    write('game/assets/scenes/old.scene.json', jsonEncode({'version': 5}));
    write('game/assets/scenes/new.scene.json', jsonEncode({'version': 99}));
    write('game/assets/scenes/bad.scene.json', '{nope');
    write('game/assets/scenes/odd.scene.json', jsonEncode({'version': '9'}));
    write('game/assets/timelines/t.timeline.json', jsonEncode({}));
    write(
      'game/assets/project/physics.json',
      jsonEncode({
        'version': 1,
        'layers': [
          {'index': '3'},
        ],
      }),
    );
    final found = {for (final f in project.checkFormats()) f.path: f};
    expect(found['assets/scenes/now.scene.json']!.old, isFalse);
    expect(found['assets/scenes/old.scene.json']!.old, isTrue);
    expect(found['assets/scenes/new.scene.json']!.tooNew, isTrue);
    expect(found['assets/scenes/bad.scene.json']!.error, isNotNull);
    expect(
      found['assets/scenes/odd.scene.json']!.error,
      contains('not a format version'),
      reason: 'a broken version is a finding, not a crash',
    );
    expect(found['assets/timelines/t.timeline.json']!.old, isTrue);
    expect(
      found['assets/project/physics.json']!.error,
      contains('not a number'),
    );
  });

  test('FormatsCheck: a versioned file that is not text is a finding', () {
    File('${tmp.path}/game/assets/scenes/raw.scene.json')
      ..createSync(recursive: true)
      ..writeAsBytesSync([0x7B, 0xFF, 0xFE, 0x7D]);
    write('game/assets/sprites/raw.png', 'not read: not a versioned file');
    final found = project.checkFormats().single;
    expect(found.path, 'assets/scenes/raw.scene.json');
    expect(found.error, startsWith('unreadable: '));
  });

  test('FormatsCheck: an animator graph is as new as what it uses', () {
    final v1 = const AnimatorGraph(states: [AnimatorState(name: 'idle')]);
    write('game/assets/sprites/a.animator.json', v1.encode());
    final blended = v1.copyWith(
      parameters: const [AnimatorParameter(name: 'speed')],
      states: const [
        AnimatorState(
          name: 'move',
          blend: AnimatorBlendTree(
            parameter: 'speed',
            motions: [AnimatorBlendMotion(clip: 'walk')],
          ),
        ),
      ],
    );
    write('game/assets/sprites/b.animator.json', blended.encode());
    final broken = blended.copyWith(parameters: const []);
    write('game/assets/sprites/c.animator.json', broken.encode());
    write('game/assets/sprites/d.animator.json', jsonEncode({'version': 3}));
    final dangling = v1.copyWith(
      transitions: const [
        AnimatorTransition(from: 'idle', to: 'gone', hasExitTime: true),
      ],
    );
    write('game/assets/sprites/e.animator.json', dangling.encode());
    final found = {for (final f in project.checkFormats()) f.path: f};
    final a = found['assets/sprites/a.animator.json']!;
    expect(
      (a.version, a.old, a.tooNew, a.error),
      (1, false, false, null),
      reason: 'version 1 is current for it',
    );
    final b = found['assets/sprites/b.animator.json']!;
    expect((b.version, b.old, b.error), (2, false, null));
    expect(
      found['assets/sprites/c.animator.json']!.error,
      contains('not a parameter'),
    );
    expect(found['assets/sprites/d.animator.json']!.tooNew, isTrue);
    expect(
      found['assets/sprites/e.animator.json']!.error,
      contains('"gone", which does not exist'),
      reason: 'the whole graph is checked, not only its blend trees',
    );
  });
}
