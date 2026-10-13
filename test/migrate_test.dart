// `just game migrate`: old saved files rewritten all or nothing, never past
// a kit's own rules or under an open editor — and `--check`, which
// `just upgrade` asks before it changes anything.

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

  /// An old scene, and a kit with no `migrate` hook when [kit].
  void old({bool kit = false}) {
    h.write(
      'assets/scenes/old.scene.json',
      jsonEncode({'version': 6, 'entities': <Object>[]}),
    );
    if (kit) {
      resolve(Directory(h.project.root), [
        package(tmp, 'my_kit', store: {'kind': 'kit'}),
      ]);
    }
  }

  void editorOpen() => h.write(EditorPresence.path, '1');

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('just_migrate_');
    h = GameHarness('${tmp.path}/game')..write('pubspec.yaml', 'name: game\n');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('rewrites old scenes, timelines and graphs in one go, as the editor '
      'writes them', () async {
    old();
    h.write('assets/timelines/t.timeline.json', '{}\n');
    final graph = jsonDecode(
      const AnimatorGraph(
        parameters: [AnimatorParameter(name: 'speed')],
        states: [
          AnimatorState(
            name: 'move',
            blend: AnimatorBlendTree(
              parameter: 'speed',
              motions: [AnimatorBlendMotion(clip: 'walk')],
            ),
          ),
        ],
      ).encode(),
    );
    // Says version 1, but uses a version 2 feature.
    h.write(
      'assets/sprites/a.animator.json',
      jsonEncode({...graph as Map, 'version': 1}),
    );
    expect(await h.just(['game', 'migrate']), 1, reason: 'asks first');
    expect('${h.err}', contains('needs a yes'));
    expect(h.read('assets/scenes/old.scene.json'), contains('"version":6'));

    expect(await h.just(['game', 'migrate', '--yes']), 0, reason: '${h.err}');
    expect('${h.out}', contains('~ assets/scenes/old.scene.json'));
    Map<String, dynamic> json(String path) =>
        jsonDecode(h.read(path)!) as Map<String, dynamic>;
    expect(
      SceneFormat.versionOf(json('assets/scenes/old.scene.json')),
      SceneFormat.current,
    );
    expect(
      h.read('assets/scenes/old.scene.json'),
      startsWith('{\n  "'),
      reason: 'indented as the editor writes it',
    );
    expect(
      TimelineFormat.versionOf(json('assets/timelines/t.timeline.json')),
      TimelineFormat.current,
    );
    expect(h.read('assets/timelines/t.timeline.json'), endsWith('}\n'));
    expect(json('assets/sprites/a.animator.json')['version'], 2);
    expect(
      await h.just(['game', 'migrate', '--yes']),
      0,
      reason: 'nothing left',
    );
    expect('${h.out}', contains('Every saved file is in its current format'));
  });

  test('a file of a kind it has no migration for is left as it is', () async {
    // An old tag library is no animator graph, whatever it holds.
    const tags = '{"version": 0, "tags": []}';
    h.write(TagsFile.path, tags);
    expect(await h.just(['game', 'migrate', '--yes']), 0, reason: '${h.err}');
    expect(h.read(TagsFile.path), tags);
    expect(
      () => FormatsCheck.migrated('tag library', tags),
      throwsArgumentError,
    );
  });

  test(
    "old files aren't rewritten past a kit that has its own rules",
    () async {
      old(kit: true);
      expect(await h.just(['game', 'migrate', '--yes']), 1);
      expect('${h.err}', contains('my_kit may migrate its own components'));
      expect('${h.err}', contains('`just game migrate --engine-only`'));
      expect(h.read('assets/scenes/old.scene.json'), contains('"version":6'));
      expect(MigrationSafety.unsafeKits(h.project), ['my_kit']);
      expect(
        await h.just(['game', 'migrate', '--yes', '--engine-only']),
        0,
        reason: '${h.err}',
      );
    },
  );

  test('nothing is rewritten while the editor has the project open', () async {
    old();
    editorOpen();
    expect(await h.just(['game', 'migrate', '--yes']), 1);
    expect('${h.err}', contains('editor has this project open'));
    expect(h.read('assets/scenes/old.scene.json'), contains('"version":6'));
    expect(await h.just(['game', 'migrate', '--yes', '--force']), 0);
  });

  test(
    'an open editor is no reason to fail when every file is current',
    () async {
      h.write(
        'assets/scenes/now.scene.json',
        jsonEncode({'version': SceneFormat.current, 'entities': <Object>[]}),
      );
      editorOpen();
      expect(
        await h.just(['game', 'migrate', '--json']),
        0,
        reason: '${h.err}',
      );
      final result = (jsonDecode('${h.out}') as Map)['result'] as Map;
      expect(result['migrated'], isEmpty, reason: '`just upgrade` reads it');
    },
  );

  group('--check', () {
    test('changes nothing, and says yes when a migration could run', () async {
      old();
      expect(
        await h.just(['game', 'migrate', '--check', '--json']),
        0,
        reason: '${h.err}',
      );
      expect(h.read('assets/scenes/old.scene.json'), contains('"version":6'));
      final result = (jsonDecode('${h.out}') as Map)['result'] as Map;
      expect(result['old'], ['assets/scenes/old.scene.json']);
    });

    test('says no while the editor is open, old files or not', () async {
      editorOpen();
      expect(await h.just(['game', 'migrate', '--check']), 1);
      expect('${h.err}', contains('Close it first'));
      expect(await h.just(['game', 'migrate', '--check', '--force']), 0);
    });

    test('says no to old files past a kit with rules of its own', () async {
      old(kit: true);
      expect(await h.just(['game', 'migrate', '--check']), 1);
      expect(
        '${h.err}',
        contains(
          '`just game migrate --engine-only` first, then `just upgrade`',
        ),
      );
      expect(await h.just(['game', 'migrate', '--check', '--engine-only']), 0);
      // No old files: the kit is in nobody's way.
      File('${h.project.root}/assets/scenes/old.scene.json').deleteSync();
      expect(await h.just(['game', 'migrate', '--check']), 0);
    });
  });
}
