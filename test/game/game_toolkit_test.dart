// The game toolkit, on every platform: the engine's versions, a new
// game's files and its entry points —
// run on the VM, and in a browser with `dart test -p chrome`
// (JavaScript) and `dart test -p chrome -c dart2wasm` (WebAssembly).

import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart';
import 'package:test/test.dart';

void main() {
  group('GameSet.bump', () {
    String set(String name) => GameSet.current[name]!.constraint;

    test('moves older constraints to the set, one line each', () {
      // just_tiled is on the set already: it stays.
      final pubspec =
          'name: game\r\n'
          'dependencies:\r\n'
          '  just_game_engine: ^1.6.0 # the engine\r\n'
          '  just_tiled: ${set('just_tiled')}\r\n'
          'dev_dependencies:\r\n'
          '  just_game_engine_editor: any\r\n';
      final (next, bumps) = GameSet.current.bump(pubspec);
      final engine = set('just_game_engine');
      expect(bumps, {
        'just_game_engine': {'from': '^1.6.0', 'to': engine},
        'just_game_engine_editor': {
          'from': 'any',
          'to': set('just_game_engine_editor'),
        },
      });
      expect(next, contains('  just_game_engine: $engine # the engine\r\n'));
      expect(next, contains('  just_tiled: ${set('just_tiled')}\r\n'));
      expect(GameSet.current.bump(next).$2, isEmpty, reason: 'on the set');
    });

    test('never moves a game ahead of the set back', () {
      const pubspec =
          'dependencies:\n'
          '  just_game_engine: ^2.1.0\n'
          '  just_physics_engine: ^3.0.0\n'
          '  just_tiled: 0.6.0\n'
          '  just_dart: ">=0.4.0 <2.0.0"\n';
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
}
