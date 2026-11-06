/// `just game check`.
library;

import 'package:just_core_cli/just_core_cli.dart';
import 'package:meta/meta.dart';

import '../game/game.dart';
import '../project/project.dart';
import '../release/release.dart';
import 'flutter_target.dart';

/// `just game check [release-imports] [release-build] [formats]`: what
/// `just check` runs for the game (release-imports and formats), and the
/// check of a release build.
///
/// A release-imports walk that could not look everywhere it had to
/// ([ReleaseImportsUnchecked]: the entry point missing, the packages never
/// fetched) fails the check, saying why: it proves nothing.
@internal
final class GameCheckCommand extends JustCommand {
  /// The command and its options.
  GameCheckCommand() {
    argParser.addOption(
      'platform',
      help: 'With release-build: the build to check (default: this desktop).',
    );
  }

  /// The checks, by name.
  static const List<String> checks = [
    'release-imports',
    'release-build',
    'formats',
  ];

  @override
  String get name => 'check';

  @override
  String get description =>
      'Check the game: that no editor code is reachable from it '
      '(release-imports), that a release build holds none (release-build), '
      'and that its saved files are in formats this engine reads (formats). '
      'With none named: release-imports and formats.';

  @override
  String get invocation =>
      '${context.invokedAs} game check [release-imports] [release-build] '
      '[formats]';

  @override
  Future<int> run() async {
    final project = requireProject();
    for (final c in rest) {
      if (!checks.contains(c)) {
        throw UsageFailure('"$c" is not a check: ${checks.join(', ')}.');
      }
    }
    final platformOption = argResults!.option('platform');
    if (platformOption != null &&
        !ReleaseBuild.platforms.contains(platformOption)) {
      throw UsageFailure(
        '--platform $platformOption: release builds can be checked for '
        '${ReleaseBuild.platforms.join(', ')}.',
      );
    }
    final want = rest.isEmpty ? {'release-imports', 'formats'} : rest.toSet();
    if (platformOption != null) want.add('release-build');
    final result = <String, Object?>{};
    var failed = false;

    if (want.contains('release-imports')) {
      final game = GameEntries.game(project.readProjectFile());
      List<String> found;
      var unchecked = const <String>[];
      try {
        found = project.editorReachableFrom(game);
      } on ReleaseImportsUnchecked catch (e) {
        found = e.reachable;
        unchecked = e.reasons;
        failed = true;
        output.line('x   ${e.message}');
      }
      result['release-imports'] = {
        'entry': game,
        'reachable': found,
        if (unchecked.isNotEmpty) 'unchecked': unchecked,
      };
      if (found.isEmpty && unchecked.isEmpty) {
        output.line('ok  No editor code is reachable from $game.');
      } else if (found.isNotEmpty) {
        failed = true;
        output.line('x   Editor code is reachable from $game:');
        for (final f in found) {
          output.line('      $f');
        }
      }
    }

    if (want.contains('release-build')) {
      final platform = platformOption ?? desktopPlatform();
      final report = project.checkReleaseBuild(platform);
      result['release-build'] = {
        'platform': platform,
        'ok': report.ok,
        'errors': report.errors,
        'warnings': report.warnings,
      };
      for (final w in report.warnings) {
        output.warn(w);
      }
      if (report.ok) {
        output.line('ok  The $platform release build holds no editor.');
      } else {
        failed = true;
        for (final e in report.errors) {
          output.line('x   $e');
        }
      }
    }

    if (want.contains('formats')) {
      final files = project.checkFormats();
      result['formats'] = [for (final f in files) f.toJson()];
      final bad = files.where((f) => f.error != null || f.tooNew).toList();
      final old = files.where((f) => f.error == null && f.old).toList();
      for (final f in bad) {
        failed = true;
        output.line(
          f.error != null
              ? 'x   ${f.path}: ${f.error}'
              : 'x   ${f.path} is a ${f.kind} from a newer engine (format '
                    'v${f.version}; this one reads up to v${f.current}).',
        );
      }
      for (final f in old) {
        output.line(
          ' !  ${f.path} is in ${f.kind} format v${f.version}: it loads'
          '${FormatsCheck.migratable.contains(f.kind) ? ', migrated as it does; `${context.invokedAs} game migrate` rewrites it in v${f.current}' : ' as it is'}.',
        );
      }
      if (bad.isEmpty) {
        output.line(
          'ok  ${files.length} saved files are in formats this engine reads.',
        );
      }
    }
    output.result = result;
    return failed ? 1 : 0;
  }
}
