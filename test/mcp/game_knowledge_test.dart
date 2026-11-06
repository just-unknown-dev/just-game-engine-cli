// What `just game mcp` reads about a game: its engine packages, and their
// API in the background — which must never fail, or the server would end.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:just_game_engine_cli/src/mcp/mcp.dart';
import 'package:test/test.dart';

import '../support/unreadable.dart';

void main() {
  late Directory tmp;
  late String game;
  late String engine;

  void write(String path, String text) =>
      (File(path)..createSync(recursive: true)).writeAsStringSync(text);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('just_knowledge_');
    game = '${tmp.path}/game';
    engine = '${tmp.path}/just_game_engine';
    write('$game/pubspec.yaml', 'name: game\n');
    write('$engine/pubspec.yaml', "name: just_game_engine\nversion: '9.9.9'\n");
    write(
      '$engine/lib/just_game_engine.dart',
      '/// The engine.\nclass Engine {}',
    );
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
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test("the game's engine packages: version and where pub took each", () {
    final knowledge = GameKnowledge.read(game);
    final p = knowledge.packages['just_game_engine']!;
    expect(p.version, '9.9.9', reason: 'quotes taken off, as pub reads it');
    expect(p.fromPubCache, isFalse, reason: 'a checkout');
    expect(knowledge.packages, isNot(contains('game')));
  });

  test('a folder the API reader trips on leaves the API read, and says '
      'what is missing', () async {
    final secret = Directory('$engine/lib/src/secret')
      ..createSync(recursive: true);
    addTearDown(() => makeReadable(secret));
    File('${secret.path}/a.dart').writeAsStringSync('class Hidden {}');
    if (!makeUnreadable(secret)) {
      markTestSkipped('this user can read any folder');
      return;
    }
    final knowledge = GameKnowledge.read(game);
    final api = await knowledge.api;
    expect(api.lookup('Engine'), hasLength(1));
    expect(api.problems.single, contains('could not be listed'));
    expect((await knowledge.search).search('engine'), isNotEmpty);
  });
}
