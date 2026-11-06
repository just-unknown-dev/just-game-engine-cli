// `just game check`: release imports, a release build and the saved
// formats.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:test/test.dart';

import '../support/fake_launcher.dart';

void main() {
  late Directory tmp;
  late GameHarness h;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('just_game_');
    // A Flutter SDK SdkLocator accepts.
    File(
      '${tmp.path}/flutter/bin/flutter${Platform.isWindows ? '.bat' : ''}',
    ).createSync(recursive: true);
    h = GameHarness('${tmp.path}/game')
      ..env = {'FLUTTER_ROOT': '${tmp.path}/flutter'}
      ..write('pubspec.yaml', 'name: game\n')
      ..write('lib/main.dart', "import 'game/app.dart';\n")
      ..write('lib/game/app.dart', '');
    resolve(Directory(h.project.root), const []);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('check', () {
    test('with none named: release imports and the saved formats', () async {
      h.write(
        'assets/scenes/old.scene.json',
        jsonEncode({'version': 6, 'entities': <Object>[]}),
      );
      expect(await h.just(['game', 'check']), 0, reason: '${h.out}');
      expect('${h.out}', contains('ok  No editor code is reachable'));
      expect('${h.out}', contains('`just game migrate` rewrites it'));
      expect('${h.out}', contains('ok  1 saved files'));

      // The tools are editor-only too.
      resolve(Directory(h.project.root), [package(tmp, 'just_core_cli')]);
      h.write('lib/game/app.dart', "import 'package:just_core_cli/x.dart';");
      expect(await h.just(['game', 'check', 'release-imports']), 1);
      expect('${h.out}', contains('package:just_core_cli/x.dart'));
    });

    test('--platform takes only the builds it can read', () async {
      expect(
        await h.just(['game', 'check', 'release-build', '--platform', 'apk']),
        ExitCodes.usage,
      );
      expect('${h.err}', contains('windows, linux, macos, web'));
      expect('${h.err}', isNot(contains('Unexpected error')));
      expect(await h.just(['game', 'check', 'nope']), ExitCodes.usage);
    });

    test("an import walk that could not look fails, saying why", () async {
      // A typo in just.json's entry, and the packages never fetched: each
      // used to pass, "No editor code is reachable", without looking.
      h.write(
        'just.json',
        jsonEncode({
          'entry': {'game': 'lib/mian.dart'},
        }),
      );
      expect(await h.just(['game', 'check', 'release-imports', '--json']), 1);
      final result = (jsonDecode('${h.out}') as Map)['result'] as Map;
      final imports = result['release-imports'] as Map;
      expect(imports['unchecked'], [contains('There is no lib/mian.dart')]);
      expect('${h.err}', isNot(contains('No editor code is reachable')));

      File('${h.project.root}/just.json').deleteSync();
      File('${h.project.root}/.dart_tool/package_config.json').deleteSync();
      h.out.clear();
      expect(await h.just(['game', 'check', 'release-imports']), 1);
      expect('${h.out}', contains('proves nothing'));
      expect('${h.out}', contains('flutter pub get'));
    });

    test('a release build with the editor fails', () async {
      h.write('just.json', jsonEncode({'title': 'Game'}));
      h.write('build/web/main.dart.js', '"Game" "Just Runtime Editor"');
      expect(await h.just(['game', 'check', '--platform', 'web']), 1);
      expect('${h.out}', contains('Just Runtime Editor'));
    });
  });
}
