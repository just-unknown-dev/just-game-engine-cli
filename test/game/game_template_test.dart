// A new game's files: the bundled templates, and the template filled
// in.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart';
import 'package:test/test.dart';

import '../../tool/bundle_templates.dart' as tool;

void main() {
  test('the bundled templates are the files in templates/', () {
    expect(
      File('lib/src/game/bundled_templates.g.dart').readAsStringSync(),
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

    test("notes for AI assistants, and their MCP server's config", () {
      final files = render('Bob');
      expect(files['AGENTS.md'], startsWith('# Bob: notes for AI assistants'));
      expect(files['AGENTS.md'], contains('engine.subsystem<T>()'));
      expect(files['CLAUDE.md'], '@AGENTS.md\n');
      for (final (path, key) in [
        ('.mcp.json', 'mcpServers'),
        ('.vscode/mcp.json', 'servers'),
      ]) {
        final config = jsonDecode(files[path]!) as Map<String, Object?>;
        final server = (config[key] as Map)['just_game_engine'] as Map;
        expect(server['command'], 'just', reason: path);
        expect(server['args'], ['game', 'mcp'], reason: path);
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

    test('the store is a dev tool from pub.dev, where just_core_cli trusts '
        'it', () {
      final store = GameSet.current['just_asset_store']!;
      expect(store.source, PackageSource.hosted);
      expect(store.dev, isTrue, reason: 'a game never ships the store');
      expect(TemplateRenderer.dependencyLines(store), [
        '  just_asset_store: ${store.constraint}',
      ]);
      // `game init` runs it without asking only because just_core_cli
      // (from 0.1.1) lists it as the ecosystem's own on pub.dev.
      expect(PluginTrust.onPubDev, contains('just_asset_store'));
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
}
