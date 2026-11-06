// `just game run`: the game or the editor, with a launcher that records
// what flutter would have run.

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
}
