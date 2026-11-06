// `just game doctor`: what would ship the editor or keep it from
// working.

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

    test('the entry point is judged by the release rules, '
        'dependencies however indented, ignores as git reads them', () async {
      h
        ..write(
          'pubspec.yaml',
          'name: game\n'
              'dependencies:\n'
              '    just_game_engine_editor:\n'
              '        path: ../editor\n',
        )
        ..write(
          'lib/main.dart',
          "import 'package:just_editor_core/just_editor_core.dart';\n"
              "import 'editor_theme.dart';\n",
        )
        ..write('.gitignore', '/.editor_backups/\n.editor_logs\n.editor_t*/\n');
      expect(await h.just(['game', 'doctor', '--json']), 1);
      final findings =
          ((jsonDecode('${h.out}') as Map)['result'] as Map)['findings']
              as List;
      String all(String severity) => [
        for (final f in findings)
          if ((f as Map)['severity'] == severity) f['message'],
      ].join('\n');
      expect(
        all('problem'),
        contains(
          'lib/main.dart imports editor code, which would ship '
          '(package:just_editor_core/just_editor_core.dart)',
        ),
      );
      expect(
        all('problem'),
        contains('just_game_engine_editor is a dependency'),
      );
      expect(all('warning'), isNot(contains('.gitignore')));
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
