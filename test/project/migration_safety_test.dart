// When old saved files may be rewritten: never past a kit with rules of its
// own, and a package whose manifest can't be read stops nothing.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:test/test.dart';

import '../support/fake_launcher.dart';

void main() {
  late Directory tmp;
  late GameHarness h;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('just_safety_');
    h = GameHarness('${tmp.path}/game')..write('pubspec.yaml', 'name: game\n');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('a kit without a migrate hook is unsafe; one with it is not', () {
    resolve(Directory(h.project.root), [
      package(tmp, 'bare_kit', store: {'kind': 'kit'}),
      package(
        tmp,
        'hooked_kit',
        store: {'kind': 'kit'},
        manifest: {
          'hooks': {'migrate': 'kit migrate'},
          'commands': [
            {'name': 'kit'},
          ],
        },
      ),
      package(tmp, 'a_tool', store: {'kind': 'editor'}),
    ]);
    expect(MigrationSafety.unsafeKits(h.project), ['bare_kit']);
  });

  test("a just_store.json that isn't UTF-8 is no kit, not a crash", () async {
    final odd = package(tmp, 'odd_kit');
    File('${odd.path}/just_store.json').writeAsBytesSync([0x7B, 0xFF, 0x7D]);
    resolve(Directory(h.project.root), [odd]);
    expect(MigrationSafety.unsafeKits(h.project), isEmpty);
    // And so `game migrate --check`, which `just upgrade` asks first.
    h.write(
      'assets/scenes/old.scene.json',
      jsonEncode({'version': 6, 'entities': <Object>[]}),
    );
    expect(await h.just(['game', 'migrate', '--check']), 0, reason: '${h.err}');
  });
}
