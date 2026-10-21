// `just game scene`: changes all or nothing, written as the editor writes
// them, and never under an open editor.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart';
import 'package:test/test.dart';

import 'support/fake_launcher.dart';

void main() {
  late Directory tmp;
  late GameHarness h;

  Future<int> just(List<String> args) => h.just(args);
  String? read(String path) => h.read(path);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('just_scene_');
    h = GameHarness(tmp.path)..write('pubspec.yaml', 'name: game\n');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('scene', () {
    test('new writes what the editor writes, and lists it', () async {
      expect(await just(['game', 'scene', 'new']), 0, reason: '${h.err}');
      expect(
        read('assets/scenes/level_01.scene.json'),
        SceneStarters.encode(SceneStarters.twoD('level_01')),
      );
      expect(await just(['game', 'scene', 'new', 'cave', '--3d']), 0);
      expect(await just(['game', 'scene', 'new', '--after', 'level_01']), 0);
      expect(SceneManifest.parse(read(SceneManifest.path)!), [
        'level_01',
        'level_02',
        'cave',
      ]);
      expect(read('assets/scenes/cave.scene.json'), contains('"mode": "3d"'));
    });

    test("new refuses a taken name or one that isn't an identifier", () async {
      await just(['game', 'scene', 'new', 'cave']);
      expect(await just(['game', 'scene', 'new', 'Cave']), 1);
      expect('${h.err}', contains('already exists'));
      expect(await just(['game', 'scene', 'new', 'class']), 1);
    });

    test('rename moves the file, the name inside and the order', () async {
      await just(['game', 'scene', 'new', 'level_01']);
      await just(['game', 'scene', 'new', 'level_02']);
      expect(await just(['game', 'scene', 'rename', 'level_01', 'intro']), 0);
      expect(read('assets/scenes/level_01.scene.json'), isNull);
      final scene = jsonDecode(read('assets/scenes/intro.scene.json')!) as Map;
      expect(scene['name'], 'intro');
      expect(SceneManifest.parse(read(SceneManifest.path)!), [
        'intro',
        'level_02',
      ]);
    });

    test('a rename in case alone keeps the scene, on any disk', () async {
      await just(['game', 'scene', 'new', 'Cave']);
      expect(
        await just(['game', 'scene', 'rename', 'Cave', 'cave']),
        0,
        reason: '${h.err}',
      );
      final files = Directory('${tmp.path}/assets/scenes')
          .listSync()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.scene.json'))
          .toList();
      expect(files, ['cave.scene.json']);
      final scene = jsonDecode(read('assets/scenes/cave.scene.json')!) as Map;
      expect(scene['name'], 'cave');
      expect(SceneManifest.parse(read(SceneManifest.path)!), ['cave']);
      expect(await just(['game', 'scene', 'rename', 'cave', 'cave']), 1);
    });

    test(
      'a rename in case alone that fails loses nothing where case counts',
      () async {
        // A case-sensitive folder on Windows (as WSL makes them), where
        // Level and level are two files.
        final cs = Directory('${tmp.path}/cs')..createSync();
        final made = Process.runSync('fsutil.exe', [
          'file',
          'setCaseSensitiveInfo',
          cs.path,
          'enable',
        ]);
        if (made.exitCode != 0) {
          markTestSkipped('fsutil could not make a case-sensitive folder');
          return;
        }
        h.project = JustProject(cs.path);
        File('${cs.path}/pubspec.yaml').writeAsStringSync('name: game\n');
        const level = '{"name": "Level", "precious": true}';
        h.project.file('assets/scenes/Level.scene.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(level);
        // scenes.json can't be written: the rename's last step fails.
        h.project.dir(SceneManifest.path).createSync();
        expect(
          await just(['game', 'scene', 'rename', 'Level', 'level', '--force']),
          1,
        );
        expect(read('assets/scenes/Level.scene.json'), level);
        expect(
          h.project.file('assets/scenes/level.scene.json').existsSync(),
          isFalse,
        );
      },
      skip: Platform.isWindows ? false : 'a case-sensitive folder on Windows',
    );

    test('only scenes are named: never a path made from a name', () async {
      h.write('assets/elsewhere.scene.json', '{}');
      expect(
        await just(['game', 'scene', 'delete', '../elsewhere', '--yes']),
        1,
      );
      expect('${h.err}', contains('There is no scene "../elsewhere"'));
      expect(read('assets/elsewhere.scene.json'), '{}');
      expect(await just(['game', 'scene', 'migrate', '../elsewhere']), 1);
      expect('${h.err}', contains('No such scene: ../elsewhere.'));
    });

    test('a scene that is not JSON is named in the message', () async {
      h.write('assets/scenes/bad.scene.json', '{nope');
      expect(await just(['game', 'scene', 'migrate']), 1);
      expect('${h.err}', contains('assets/scenes/bad.scene.json is not valid'));
    });

    test('migrate: a broken version stops it, named; a newer scene stays, '
        'said so', () async {
      final old = jsonEncode({'version': 5, 'name': 'old', 'entities': []});
      h
        ..write('assets/scenes/old.scene.json', old)
        ..write('assets/scenes/odd.scene.json', jsonEncode({'version': 'x'}));
      expect(await just(['game', 'scene', 'migrate']), 1);
      expect('${h.err}', contains('assets/scenes/odd.scene.json'));
      expect(read('assets/scenes/old.scene.json'), old, reason: 'none written');

      h
        ..write('assets/scenes/odd.scene.json', jsonEncode({'version': 99}))
        ..write('assets/scenes/old.scene.json', jsonEncode({'version': 99}));
      h.err.clear();
      h.out.clear();
      expect(await just(['game', 'scene', 'migrate']), 0);
      expect('${h.err}', contains('odd is from a newer engine'));
      expect('${h.out}', contains('No scene to migrate.'));
    });

    test('validate reports a scene whose entities are not a list, and goes '
        'on', () async {
      h
        ..write(
          'assets/scenes/a.scene.json',
          jsonEncode({'version': SceneFormat.current, 'entities': {}}),
        )
        ..write(
          'assets/scenes/b.scene.json',
          jsonEncode({'version': SceneFormat.current, 'entities': []}),
        );
      expect(await just(['game', 'scene', 'validate']), 1);
      expect('${h.out}', contains('a: its "entities" is not a list'));
      expect('${h.out}', contains('ok  b'));
    });

    test('validate takes an instance of a prefab file for an entity', () async {
      h
        ..write(
          'assets/scenes/a.scene.json',
          jsonEncode({
            'version': SceneFormat.current,
            'entities': [
              {'name': 'Crate', 'prefab': {'path': 'assets/prefabs/crate.prefab.json'}},
            ],
          }),
        )
        ..write(
          'assets/scenes/b.scene.json',
          jsonEncode({
            'version': SceneFormat.current,
            'entities': [
              {'name': 'Crate', 'prefab': {'path': ''}},
            ],
          }),
        );
      expect(await just(['game', 'scene', 'validate']), 1);
      expect('${h.out}', contains('ok  a'));
      expect('${h.out}', contains('b: "Crate" is an instance of no prefab file'));
    });

    test('a folder named like a scene is no scene', () async {
      Directory(
        '${tmp.path}/assets/scenes/odd.scene.json',
      ).createSync(recursive: true);
      await just(['game', 'scene', 'new', 'cave']);
      expect(await just(['game', 'scene', 'list']), 0, reason: '${h.err}');
      expect('${h.out}', isNot(contains('odd')));
    });

    test('delete asks, keeps a copy in the trash, and unlists it', () async {
      await just(['game', 'scene', 'new', 'cave']);
      expect(
        await just(['game', 'scene', 'delete', 'cave']),
        1,
        reason: 'no --yes',
      );
      expect(read('assets/scenes/cave.scene.json'), isNotNull);
      expect(await just(['game', 'scene', 'delete', 'cave', '--yes']), 0);
      expect(read('assets/scenes/cave.scene.json'), isNull);
      expect(SceneManifest.parse(read(SceneManifest.path)!), isEmpty);
      final trash = Directory('${tmp.path}/.editor_trash/scenes');
      expect(
        trash.listSync(recursive: true).whereType<File>().single.path,
        endsWith('cave.scene.json'),
      );
    });

    test('order sets the play order from scenes that exist', () async {
      await just(['game', 'scene', 'new', 'a']);
      await just(['game', 'scene', 'new', 'b']);
      expect(await just(['game', 'scene', 'order', 'b', 'a']), 0);
      expect(SceneManifest.parse(read(SceneManifest.path)!), ['b', 'a']);
      expect(await just(['game', 'scene', 'order', 'nope']), 1);
    });

    test('list says how to make the first one', () async {
      expect(await just(['game', 'scene', 'list']), 0);
      expect('${h.out}', contains('`just game scene new level_01`'));
      expect(h.project.editorIsOpen(), isFalse, reason: 'no heartbeat');
    });

    test('nothing is written while the editor has the project open', () async {
      h.project.file(EditorPresence.path)
        ..createSync(recursive: true)
        ..writeAsStringSync('1');
      expect(await just(['game', 'scene', 'new', 'cave']), 1);
      expect('${h.err}', contains('editor has this project open'));
      expect(read('assets/scenes/cave.scene.json'), isNull);
      expect(await just(['game', 'scene', 'new', 'cave', '--force']), 0);
      // A heartbeat that stopped long ago is a closed editor.
      h.project
          .file(EditorPresence.path)
          .setLastModifiedSync(
            DateTime.now().subtract(const Duration(minutes: 1)),
          );
      expect(h.project.editorIsOpen(), isFalse);
    });

    test(
      'migrate rewrites old scenes, and validate finds broken ones',
      () async {
        final old = {
          'version': 5,
          'name': 'old',
          'entities': [
            {'name': 'A', 'parentName': null, 'components': <Object>[]},
          ],
        };
        h.project.file('assets/scenes/old.scene.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode(old));
        expect(await just(['game', 'scene', 'migrate']), 0, reason: '${h.err}');
        expect(
          SceneFormat.versionOf(
            jsonDecode(read('assets/scenes/old.scene.json')!)
                as Map<String, dynamic>,
          ),
          SceneFormat.current,
        );
        h.project
            .file('assets/scenes/bad.scene.json')
            .writeAsStringSync(
              jsonEncode({
                'version': 8,
                'entities': [
                  {
                    'name': 'A',
                    'parentName': 'Ghost',
                    'components': <Object>[],
                  },
                  {'name': 'A', 'parentName': null, 'components': <Object>[]},
                ],
              }),
            );
        expect(await just(['game', 'scene', 'validate']), 1);
        expect('${h.out}', contains('two entities called "A"'));
        expect('${h.out}', contains('"Ghost"'));
      },
    );
  });
}
