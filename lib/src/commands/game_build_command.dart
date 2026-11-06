/// `just game build`.
library;

import 'package:just_core_cli/just_core_cli.dart';
import 'package:meta/meta.dart';

import '../game/game.dart';
import '../project/project.dart';
import '../release/release.dart';
import 'flutter_target.dart';

/// `just game build <platform> [flutter build options]`: a release build,
/// then the proof that it holds no editor.
///
/// The game's source is walked first ([ProjectGame.editorReachableFrom]):
/// quick, and a game that reaches the editor is refused before it builds.
/// A walk that could not look — the packages not fetched yet, which
/// `flutter build` fetches — is a warning before the build; then the build
/// is checked, or, for a platform whose build the check can't read
/// (`apk`, `ios`…), the source is walked again, and the command fails when
/// it still can't be.
@internal
final class GameBuildCommand extends JustCommand {
  /// The command and its options.
  GameBuildCommand() {
    argParser.addFlag(
      'editor-entry',
      negatable: false,
      help:
          "Build the editor's entry point (lib/main_editor.dart) instead: its "
          'release build must be the game, with no editor in it.',
    );
  }

  @override
  String get name => 'build';

  @override
  String get description =>
      'A release build, then a check that it holds no editor. Anything '
      'after `--` goes to `flutter build`.';

  @override
  String get invocation =>
      '${context.invokedAs} game build <platform> [options]';

  @override
  Future<int> run() async {
    final project = requireProject();
    if (rest.isEmpty) {
      throw const UsageFailure(
        'build needs a platform: windows, macos, linux, web, apk, ios…',
      );
    }
    final platform = rest.first;
    final file = project.readProjectFile();
    final editorEntry = argResults!.flag('editor-entry');
    final entry = editorEntry
        ? GameEntries.editor(file)
        : GameEntries.game(file);
    if (!project.file(entry).existsSync()) {
      throw CommandFailure(
        "There is no $entry to build: is just.json's entry right?",
      );
    }
    final rules = project.releaseRules();
    final readable = ReleaseBuild.platforms.contains(platform);

    // The source first: quick, and a failure here saves a build. The
    // editor's entry point imports the editor on purpose (inside
    // `if (kDebugMode)`), so only its build can say what ships.
    var walked = editorEntry;
    if (!editorEntry) {
      walked = _walk(project, entry, rules, before: true);
    }

    final code = await context.launcher.run(
      flutterFor(this, project).flutter,
      ['build', platform, '--release', '-t', entry, ...rest.skip(1)],
      workingDirectory: project.root,
      toStderr: output.json,
    );
    if (code != 0) {
      throw CommandFailure('flutter build failed (exit code $code).');
    }
    if (!readable) {
      // `flutter build` has fetched the packages: what the walk could not
      // look at before, it can now.
      if (!walked) _walk(project, entry, rules, before: false);
      output
        ..result = {'platform': platform, 'entry': entry, 'checked': false}
        ..line(
          'Built. (The build check reads windows, macos, linux and web '
          'builds; $platform builds are checked through their source only.)',
        );
      return 0;
    }
    final report = project.checkReleaseBuild(platform, rules: rules);
    for (final n in report.notes) {
      output.line('  $n');
    }
    for (final w in report.warnings) {
      output.warn(w);
    }
    for (final e in report.errors) {
      output.line('x $e');
    }
    output.result = {
      'platform': platform,
      'entry': entry,
      'checked': true,
      'ok': report.ok,
      'errors': report.errors,
      'warnings': report.warnings,
    };
    if (!report.ok) {
      throw CommandFailure('The $platform release build holds editor code.');
    }
    output.line('OK: the $platform release build holds no editor.');
    return 0;
  }

  /// Walks [entry]'s imports, and says whether it could look everywhere.
  /// Throws [CommandFailure] when editor code is reachable, and — after the
  /// build ([before] false) — when the walk still could not look.
  bool _walk(
    JustProject project,
    String entry,
    ReleaseRules rules, {
    required bool before,
  }) {
    List<String> reachable;
    try {
      reachable = project.editorReachableFrom(entry, rules: rules);
    } on ReleaseImportsUnchecked catch (e) {
      if (e.reachable.isEmpty) {
        if (!before) {
          throw CommandFailure(
            'The build is made, but unchecked. ${e.message}',
          );
        }
        output.warn(
          '${e.message} It is checked again once `flutter build` has '
          'fetched the packages.',
        );
        return false;
      }
      reachable = e.reachable;
    }
    if (reachable.isNotEmpty) {
      throw CommandFailure(
        'Editor code is reachable from $entry, so it would ship:\n'
        '${reachable.map((r) => '  $r').join('\n')}',
      );
    }
    return true;
  }
}
