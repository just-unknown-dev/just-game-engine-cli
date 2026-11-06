// `just game mcp`'s server: its tools over a real MCP connection to a
// small game.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:just_game_engine_cli/src/mcp/game_knowledge.dart';
import 'package:just_game_engine_cli/src/mcp/game_mcp_server.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  group('the server', () {
    late Directory tmp;
    late ServerConnection server;
    late List<List<String>> ran;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('just_mcp_game_');
      final game = '${tmp.path}/game';
      final engine = '${tmp.path}/just_game_engine';
      void write(String path, String text) =>
          (File(path)..createSync(recursive: true)).writeAsStringSync(text);
      write('$game/pubspec.yaml', 'name: game\n');
      write('$engine/pubspec.yaml', 'name: just_game_engine\nversion: 9.9.9\n');
      write(
        '$engine/MIGRATION.md',
        '# Migrating\n\n## Engine\n\nOne engine.\n',
      );
      write('$engine/lib/just_game_engine.dart', "export 'src/engine.dart';");
      write('$engine/lib/src/engine.dart', '''
/// The engine.
class Engine {
  /// One engine.
  Engine();

  /// A subsystem.
  T? subsystem<T extends Object>() => null;

  @Deprecated('Use subsystem<T>().')
  T? getSystem<T extends Object>() => null;
}
''');
      write('$engine/doc/guides/README.md', '''
# Guides

## Core

- [Engine & lifecycle](engine.md): Create an engine and run it.
''');
      write('$engine/doc/guides/engine.md', '''
# Engine & lifecycle

_Core_ · Create an engine and run it.

## Creating an engine

Call `Engine()` once and keep it.

## Pausing

`engine.pause()` stops the fixed steps.
''');
      write(
        '$game/.dart_tool/package_config.json',
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'just_game_engine',
              'rootUri': Uri.directory(engine).toString(),
              'packageUri': 'lib/',
            },
            {'name': 'game', 'rootUri': '../', 'packageUri': 'lib/'},
          ],
        }),
      );
      ran = [];
      final channel = StreamChannelController<String>();
      GameMcpServer(
        channel.local,
        knowledge: GameKnowledge.read(game),
        editorOpen: () => true,
        runJust: (args) async {
          ran.add(args);
          return switch (args) {
            ['game', 'scene', 'list'] => (
              exitCode: 0,
              document: {
                'ok': true,
                'result': [
                  {'name': 'level_01', 'mode': '2d', 'entities': 3},
                ],
              },
              messages: '',
            ),
            ['game', 'scene', 'validate', ...] => (
              exitCode: 1,
              document: {
                'ok': false,
                'result': {
                  'scenes': {
                    'level_01': ['two entities called "Hero"'],
                  },
                  'missing': [],
                },
              },
              messages: '',
            ),
            _ => (exitCode: 0, document: null, messages: ''),
          };
        },
      );
      final client = MCPClient(Implementation(name: 'test', version: '0'));
      server = client.connectServer(channel.foreign);
      final init = await server.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: client.capabilities,
          clientInfo: client.implementation,
        ),
      );
      server.notifyInitialized();
      expect(init.instructions, contains('just_game_engine 9.9.9'));
      expect(init.instructions, contains('engine.subsystem<T>()'));
    });

    tearDown(() async {
      await server.shutdown();
      tmp.deleteSync(recursive: true);
    });

    Future<(String, bool)> call(
      String tool, [
      Map<String, Object?>? args,
    ]) async {
      final r = await server.callTool(
        CallToolRequest(name: tool, arguments: args ?? const {}),
      );
      return (
        r.content.map((c) => (c as TextContent).text).join('\n'),
        r.isError ?? false,
      );
    }

    test('lists its tools, all read-only', () async {
      final tools = (await server.listTools()).tools;
      expect(tools.map((t) => t.name), [
        'project_info',
        'search_docs',
        'read_doc',
        'get_api',
        'list_scenes',
        'validate_scenes',
        'check_game',
      ]);
      for (final t in tools) {
        expect(t.toolAnnotations?.readOnlyHint, isTrue, reason: t.name);
      }
    });

    test('project_info: the versions, the editor and the scenes', () async {
      final (text, _) = await call('project_info');
      expect(text, contains('just_game_engine 9.9.9'));
      expect(text, contains('Level editor: open'));
      expect(text, contains('Guides: 1'));
      expect(text, contains('name: level_01'));
    });

    test('search_docs finds guides, notes and the API', () async {
      final (text, error) = await call('search_docs', {'query': 'pause'});
      expect(error, isFalse);
      expect(text, contains('[guide] Engine & lifecycle › Pausing'));
      expect(text, contains('read_doc(doc: "engine", section: "Pausing")'));
      final (api, _) = await call('search_docs', {
        'query': 'subsystem',
        'kind': 'api',
      });
      expect(api, contains('get_api(symbol: "Engine.subsystem")'));
      expect(api, isNot(contains('[guide]')));
    });

    test('read_doc lists, reads whole and reads a section', () async {
      final (list, _) = await call('read_doc');
      expect(list, contains('- engine: Engine & lifecycle.'));
      expect(list, contains('just_game_engine/MIGRATION.md'));
      final (whole, _) = await call('read_doc', {'doc': 'engine'});
      expect(whole, contains('Call `Engine()` once'));
      expect(whole, contains('engine.justunknown.com/docs/engine'));
      final (part, _) = await call('read_doc', {
        'doc': 'engine',
        'section': 'paus',
      });
      expect(part, contains('## Pausing'));
      expect(part, isNot(contains('Call `Engine()`')));
      final (note, _) = await call('read_doc', {
        'doc': 'just_game_engine/MIGRATION.md',
      });
      expect(note, contains('One engine.'));
      final (missing, error) = await call('read_doc', {'doc': 'nope'});
      expect(error, isTrue);
      expect(missing, contains('- engine:'));
    });

    test('get_api: the signature, import, members and deprecations', () async {
      final (type, _) = await call('get_api', {'symbol': 'Engine'});
      expect(
        type,
        contains("import 'package:just_game_engine/just_game_engine.dart';"),
      );
      expect(type, contains('## Constructors'));
      expect(
        type,
        contains('`T? subsystem<T extends Object>()` — A subsystem.'),
      );
      expect(type, contains('DEPRECATED: Use subsystem<T>().'));
      final (member, _) = await call('get_api', {'symbol': 'Engine.getSystem'});
      expect(member, contains('**Deprecated:** Use subsystem<T>().'));
      expect(member, contains('Member of: class Engine'));
      final (near, error) = await call('get_api', {'symbol': 'Engin'});
      expect(error, isTrue);
      expect(near, contains('Closest: Engine'));
    });

    test('validate_scenes and check_game run the commands', () async {
      final (scenes, error) = await call('validate_scenes', {
        'scenes': ['level_01'],
      });
      expect(error, isTrue);
      expect(scenes, contains('- level_01: two entities called "Hero"'));
      await call('check_game');
      expect(
        ran,
        containsAll([
          ['game', 'scene', 'validate', 'level_01'],
          ['game', 'doctor'],
          ['game', 'check'],
        ]),
      );
    });
  });
}
