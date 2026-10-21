// `just game run`, `build`, `check` and `doctor`, with a launcher that
// records what flutter would have run.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:test/test.dart';

import 'support/fake_launcher.dart';

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

  group('run', () {
    test("runs the game, or the editor's entry on this desktop", () async {
      expect(await h.just(['game', 'run']), 0);
      expect(h.launcher.runs.single.arguments, ['run', '-t', 'lib/main.dart']);
      h.launcher.runs.clear();
      expect(await h.just(['game', 'run', '--editor', '--', '--x']), 0);
      final args = h.launcher.runs.single.arguments;
      expect(args.take(3), ['run', '-t', 'lib/main_editor.dart']);
      expect(args[3], '-d');
      expect(args.last, '--x');
      expect('${h.out}', isEmpty, reason: "flutter's output is the run's");
    });

    test("takes the entry points from just.json's entry", () async {
      h.write(
        'just.json',
        jsonEncode({
          'entry': {'game': 'lib/play.dart', 'editor': 'lib/edit.dart'},
        }),
      );
      await h.just(['game', 'run', '--profile']);
      expect(h.launcher.runs.single.arguments, [
        'run',
        '-t',
        'lib/play.dart',
        '--profile',
      ]);
    });

    test('the editor in a release build is refused', () async {
      expect(
        await h.just(['game', 'run', '--editor', '--release']),
        ExitCodes.usage,
      );
      expect(h.launcher.runs, isEmpty);
    });
  });

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
  });

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

    test('a release build with the editor fails', () async {
      h.write('just.json', jsonEncode({'title': 'Game'}));
      h.write('build/web/main.dart.js', '"Game" "Just Runtime Editor"');
      expect(await h.just(['game', 'check', '--platform', 'web']), 1);
      expect('${h.out}', contains('Just Runtime Editor'));
    });
  });

  group('doctor', () {
    test('finds what would ship the editor or keep it from working', () async {
      h
        ..write(
          'pubspec.yaml',
          'name: game\r\n'
              'dependencies:\r\n'
              '  just_game_engine_editor: ^0.1.0-dev.1\r\n'
              '  just_ui_editor: ^0.1.0\r\n',
        )
        ..write(
          'lib/main_editor.dart',
          'void main() { if (!kDebugMode) return; }',
        )
        ..write('lib/main.dart', "import 'editor/editor_wiring.dart';")
        ..write(
          GameTemplate.debugEntitlements,
          '<plist>\n<dict>\n</dict>\n</plist>\n',
        );
      expect(await h.just(['game', 'doctor', '--json']), 1);
      final findings =
          ((jsonDecode('${h.out}') as Map)['result'] as Map)['findings']
              as List;
      String all(String severity) => [
        for (final f in findings)
          if ((f as Map)['severity'] == severity) f['message'],
      ].join('\n');
      expect(all('problem'), contains('has no `if (kDebugMode)`'));
      expect(all('problem'), contains('lib/main.dart imports editor code'));
      expect(
        all('problem'),
        contains('just_game_engine_editor is a dependency'),
      );
      expect(all('problem'), isNot(contains('just_ui_editor')));
      expect(all('warning'), contains('.editor_backups/'));
      expect(all('warning'), contains("Asset Store can't connect"));
    });

    test('a game set up as `just create` makes it passes', () async {
      h
        ..write(
          'lib/main_editor.dart',
          'Future<void> main() async { if (kDebugMode) {} }',
        )
        ..write('.gitignore', GameTemplate.withEditorIgnores(''))
        ..write(
          GameTemplate.debugEntitlements,
          GameTemplate.withNetworkClient('<dict>\n</dict>\n'),
        );
      expect(await h.just(['game', 'doctor']), 0, reason: '${h.out}');
      expect('${h.out}', contains('keeps the editor to debug builds'));
    });
  });
}
