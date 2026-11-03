// `just game mcp`: the API read from source, the search, and the server's
// tools over a real MCP connection to a small game.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:just_game_engine_cli/src/mcp/dart_api.dart';
import 'package:just_game_engine_cli/src/mcp/game_knowledge.dart';
import 'package:just_game_engine_cli/src/mcp/game_mcp_server.dart';
import 'package:just_game_engine_cli/src/mcp/text_search.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  group('the API from source', () {
    DartFileScan scan(String source) =>
        scanDartSource(source, package: 'p', file: 'lib/a.dart');

    ApiDeclaration only(DartFileScan s, String name) =>
        s.declarations.singleWhere((d) => d.name == name);

    test('a class: its doc, header, constructors and members', () {
      final s = scan(r'''
/// A body that moves.
///
/// More detail.
class Body extends Component with Movable implements Thing {
  /// Makes one.
  Body({this.speed = 1.0, Map<String, int> extra = const {}})
    : _x = {'a': 1}, assert(speed >= 0) {
    if (speed > 2) { print('${speed + {1: 2}.length} }'); }
  }

  Body.named(double s) : this(speed: s);

  factory Body.fromJson(Map<String, Object?> json) => Body(speed: (json['s'] as num?)?.toDouble() ?? 0);

  /// How fast.
  double speed;

  final Map<String, int> _x;

  /// The default.
  static const double defaultSpeed = 2.5;

  /// Whether it moves.
  bool get moving => speed > 0 && {1, 2}.isNotEmpty;

  set moving(bool value) {
    speed = value ? 1 : 0;
  }

  @override
  void update(double dt) {
    final s = '}';
  }

  @Deprecated('Use update instead.')
  void tick(double dt) => update(dt);

  bool operator ==(Object other) => other is Body;

  void operator []=(int i, double v) {}

  void Function(int)? onHit;

  void _hidden() {}
}

class _Private { void visible() {} }
''');
      final body = only(s, 'Body');
      expect(body.kind, 'class');
      expect(body.doc, startsWith('A body that moves.'));
      expect(body.summary, 'A body that moves.');
      expect(body.supertypes, ['Component', 'Movable', 'Thing']);
      expect(s.declarations.map((d) => d.name), ['Body']);
      final members = {for (final m in body.members) m.name: m};
      expect(members.keys, [
        'Body',
        'Body.named',
        'Body.fromJson',
        'speed',
        'defaultSpeed',
        'moving',
        'update',
        'tick',
        'operator ==',
        'operator []=',
        'onHit',
      ]);
      expect(
        members['Body']!.signature,
        'Body({this.speed = 1.0, Map<String, int> extra = const {}})',
      );
      expect(members['Body']!.doc, 'Makes one.');
      expect(members['Body.fromJson']!.kind, 'constructor');
      expect(members['speed']!.signature, 'double speed');
      expect(
        members['defaultSpeed']!.signature,
        'static const double defaultSpeed = 2.5',
      );
      expect(
        [
          for (final m in body.members)
            if (m.name == 'moving') '${m.kind}: ${m.signature}',
        ],
        ['getter: bool get moving', 'setter: set moving(bool value)'],
      );
      expect(members['update']!.isOverride, isTrue);
      expect(members['tick']!.deprecated, 'Use update instead.');
      expect(members['onHit']!.kind, 'field');
      expect(members['Body']!.line, 6);
    });

    test('enums, mixins, extensions, typedefs and top-level names', () {
      final s = scan(r'''
/// Which way.
enum Side {
  /// Left.
  left,
  @Deprecated('no') right('r'),
  up;

  const Side([this.code = '']);
  final String code;
  bool get vertical => this == up;
}

mixin Movable on Component { void move() {} }

extension BodyX on Body { double get half => speed / 2; }

typedef Hit = void Function(Body a, {int force});

/// Two.
const int two = 2;

Engine makeEngine({int fps = 60}) => Engine();

int _secret = 1;
''');
      final side = only(s, 'Side');
      expect(side.kind, 'enum');
      expect(side.values, ['left', 'right', 'up']);
      expect(side.members.map((m) => m.name), ['code', 'vertical']);
      expect(only(s, 'Movable').kind, 'mixin');
      expect(only(s, 'Movable').supertypes, ['Component']);
      expect(only(s, 'BodyX').kind, 'extension');
      expect(only(s, 'BodyX').members.single.name, 'half');
      expect(
        only(s, 'Hit').signature,
        'typedef Hit = void Function(Body a, {int force})',
      );
      expect(only(s, 'two').signature, 'const int two = 2');
      expect(only(s, 'makeEngine').kind, 'function');
      expect(s.declarations.any((d) => d.name == '_secret'), isFalse);
    });

    test('exports, parts and libraries across packages', () {
      final tmp = Directory.systemTemp.createTempSync('just_mcp_api_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      void write(String path, String text) => (File(
        '${tmp.path}/$path',
      )..createSync(recursive: true)).writeAsStringSync(text);
      write('just_game_engine/lib/just_game_engine.dart', '''
export 'src/world.dart' hide Internal;
export 'package:just_inputs/just_inputs.dart' show InputAction;
''');
      write('just_game_engine/lib/src/world.dart', '''
part 'world_part.dart';
/// The world.
class World {}
class Internal {}
class Hidden {}
''');
      write('just_game_engine/lib/src/world_part.dart', '''
part of 'world.dart';
class FromPart extends World {}
''');
      write('just_game_engine/lib/src/hidden.dart', 'class NotExported {}');
      write('just_inputs/lib/just_inputs.dart', "export 'src/a.dart';");
      write('just_inputs/lib/src/a.dart', '''
class InputAction {}
class InputMap {}
''');
      final api = ApiIndex.read({
        'just_game_engine': '${tmp.path}/just_game_engine',
        'just_inputs': '${tmp.path}/just_inputs',
      });
      final names = api.declarations.map((d) => d.name).toSet();
      expect(names, {'World', 'Hidden', 'FromPart', 'InputAction', 'InputMap'});
      expect(api.lookup('InputAction').single.libraries, [
        'package:just_game_engine/just_game_engine.dart',
        'package:just_inputs/just_inputs.dart',
      ]);
      expect(api.lookup('InputMap').single.libraries, [
        'package:just_inputs/just_inputs.dart',
      ]);
      expect(api.subtypesOf('World').map((d) => d.name), ['FromPart']);
      expect(api.lookup('world').single.doc, 'The world.');
      expect(api.similar('Wrold'), contains('World'));
    });
  });

  group('search', () {
    test('splits names and finds them whole', () {
      expect(tokens('CharacterBody2DComponent moves'), [
        'characterbody2dcomponent',
        'character',
        'body',
        '2d',
        'component',
        'move',
      ]);
      final index = SearchIndex([
        const SearchEntry(
          kind: 'api',
          title: 'CharacterBody2DComponent',
          text: 'class CharacterBody2DComponent A character the game moves.',
          ref: {'symbol': 'CharacterBody2DComponent'},
        ),
        const SearchEntry(
          kind: 'guide',
          title: '2D physics › Bodies',
          text: 'Rigid bodies fall; a body is pushed by forces.',
          ref: {'doc': 'physics-2d'},
        ),
      ]);
      expect(
        index.search('CharacterBody2DComponent').first.entry.title,
        'CharacterBody2DComponent',
      );
      expect(index.search('rigid body forces').first.entry.kind, 'guide');
      expect(index.search('body', kinds: {'api'}).single.entry.kind, 'api');
      expect(index.search('the of'), isEmpty);
    });
  });

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
