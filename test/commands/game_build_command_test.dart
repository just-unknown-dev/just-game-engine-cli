// `just game build`: the source walked before the build, the build
// checked after it, with a launcher that records what flutter would have
// run.

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

  group('build', () {
    test(
      'a game that reaches the editor is refused before it builds',
      () async {
        h.write('lib/game/app.dart', "import '../editor/wiring.dart';");
        h.write('lib/editor/wiring.dart', '');
        expect(await h.just(['game', 'build', 'windows']), 1);
        expect(
          '${h.err}',
          contains('Editor code is reachable from lib/main.dart'),
        );
        expect(h.launcher.runs, isEmpty);
      },
    );

    test(
      'a build the check cannot read is checked through its source',
      () async {
        expect(
          await h.just(['game', 'build', 'apk', '--json', '--', '--split']),
          0,
          reason: '${h.err}',
        );
        expect(h.launcher.runs.single.arguments, [
          'build',
          'apk',
          '--release',
          '-t',
          'lib/main.dart',
          '--split',
        ]);
        expect(h.launcher.runs.single.toStderr, isTrue);
        final result = (jsonDecode('${h.out}') as Map)['result'] as Map;
        expect(result['checked'], isFalse);
      },
    );

    test(
      'a release build is checked for the editor once it is built',
      () async {
        h.launcher.exitCodeFor = (args) {
          // What `flutter build web` leaves: the game, without the editor.
          h.write('build/web/main.dart.js', '"Game" MaterialApp');
          return 0;
        };
        h.write('just.json', jsonEncode({'title': 'Game'}));
        expect(await h.just(['game', 'build', 'web']), 0, reason: '${h.err}');
        expect('${h.out}', contains('the web release build holds no editor'));
        h.launcher.exitCodeFor = (args) {
          h.write('build/web/main.dart.js', '"Game" "Just Runtime Editor"');
          return 0;
        };
        expect(await h.just(['game', 'build', 'web']), 1);
        expect('${h.out}', contains('Just Runtime Editor'));
      },
    );

    test('needs a platform', () async {
      expect(await h.just(['game', 'build']), ExitCodes.usage);
    });

    test('an entry point that is not there is refused before it builds', () {
      h.write(
        'just.json',
        jsonEncode({
          'entry': {'game': 'lib/mian.dart'},
        }),
      );
      return h.just(['game', 'build', 'web']).then((code) {
        expect(code, 1);
        expect('${h.err}', contains('There is no lib/mian.dart'));
        expect(h.launcher.runs, isEmpty);
      });
    });

    group('packages not fetched yet', () {
      setUp(
        () => File(
          '${h.project.root}/.dart_tool/package_config.json',
        ).deleteSync(),
      );

      test('a build the check reads: a warning, then the build checked', () {
        h.write('just.json', jsonEncode({'title': 'Game'}));
        h.launcher.exitCodeFor = (args) {
          h.write('build/web/main.dart.js', '"Game" MaterialApp');
          return 0;
        };
        return h.just(['game', 'build', 'web']).then((code) {
          expect(code, 0, reason: '${h.err}');
          expect('${h.err}', contains('proves nothing'));
          expect('${h.out}', contains('the web release build holds no editor'));
        });
      });

      test('one it cannot read: the source walked again after the build, '
          'and refused if it still cannot be', () async {
        expect(await h.just(['game', 'build', 'apk']), 1);
        expect('${h.err}', contains('The build is made, but unchecked.'));

        // `flutter build` fetches the packages, as a real one does.
        h.launcher.exitCodeFor = (args) {
          resolve(Directory(h.project.root), const []);
          return 0;
        };
        expect(await h.just(['game', 'build', 'apk']), 0, reason: '${h.err}');
      });

      test(
        "--editor-entry doesn't walk the source: its build is the proof",
        () async {
          h.write('lib/main_editor.dart', "import 'package:gone/gone.dart';");
          h.write('just.json', jsonEncode({'title': 'Game'}));
          h.launcher.exitCodeFor = (args) {
            h.write('build/web/main.dart.js', '"Game" MaterialApp');
            return 0;
          };
          expect(
            await h.just(['game', 'build', 'web', '--editor-entry']),
            0,
            reason: '${h.err}',
          );
          expect('${h.err}', isNot(contains('proves nothing')));
          expect(
            h.launcher.runs.single.arguments,
            contains('lib/main_editor.dart'),
          );
        },
      );
    });
  });
}
