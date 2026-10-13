/// `just game run`, `just game build` and `just game check`.
library;

import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_core_cli/project.dart';

import '../project/game_entries.dart';
import '../project/game_project.dart';
import '../release/formats_check.dart';
import '../release/release_build.dart';

String _desktop() => Platform.isWindows
    ? 'windows'
    : Platform.isMacOS
    ? 'macos'
    : 'linux';

FlutterSdk _sdk(JustCommand c, JustProject project) =>
    SdkLocator.locate(project.root, environment: c.context.environment) ??
    (throw const CommandFailure(
      'Flutter was not found. Install it, put it on the PATH, or set '
      'FLUTTER_ROOT.',
    ));

/// `just game run [--editor] [flutter run options]`: the game, or the game
/// with the editor over it.
final class GameRunCommand extends JustCommand {
  /// The command and its options.
  GameRunCommand() {
    argParser
      ..addFlag(
        'editor',
        abbr: 'e',
        negatable: false,
        help: 'Run the game with the editor over it (desktop, debug).',
      )
      ..addOption(
        'device',
        abbr: 'd',
        help: 'The device to run on (default for the editor: this desktop).',
      )
      ..addFlag('profile', negatable: false, help: 'A profile build.')
      ..addFlag('release', negatable: false, help: 'A release build.');
  }

  @override
  String get name => 'run';

  @override
  String get description =>
      'Run the game, or (--editor) the game with the editor. Anything after '
      '`--` goes to `flutter run`.';

  /// What `flutter run` prints is the run's output: no JSON document.
  @override
  bool get printsOwnDocument => true;

  @override
  Future<int> run() async {
    final project = requireProject();
    final file = project.readProjectFile();
    final editor = argResults!.flag('editor');
    if (editor &&
        (argResults!.flag('release') || argResults!.flag('profile'))) {
      throw const UsageFailure(
        'The editor runs in debug builds only: a release build of it is the '
        'game. Leave out --editor to run the game in release.',
      );
    }
    final device = argResults!.option('device') ?? (editor ? _desktop() : null);
    final args = [
      'run',
      '-t',
      editor ? GameEntries.editor(file) : GameEntries.game(file),
      if (device != null) ...['-d', device],
      if (argResults!.flag('release')) '--release',
      if (argResults!.flag('profile')) '--profile',
      ...rest,
    ];
    output.detail('flutter ${args.join(' ')}');
    return context.launcher.run(
      _sdk(this, project).flutter,
      args,
      workingDirectory: project.root,
    );
  }
}

/// `just game build <platform> [flutter build options]`: a release build,
/// then the proof that it holds no editor.
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
    final game = GameEntries.game(file);
    final entry = argResults!.flag('editor-entry')
        ? GameEntries.editor(file)
        : game;

    // The source first: quick, and a failure here saves a build.
    final rules = project.releaseRules();
    final reachable = project.editorReachableFrom(entry, rules: rules);
    if (reachable.isNotEmpty && entry == game) {
      throw CommandFailure(
        'Editor code is reachable from $entry, so it would ship:\n'
        '${reachable.map((r) => '  $r').join('\n')}',
      );
    }

    final code = await context.launcher.run(
      _sdk(this, project).flutter,
      ['build', platform, '--release', '-t', entry, ...rest.skip(1)],
      workingDirectory: project.root,
      toStderr: output.json,
    );
    if (code != 0) {
      throw CommandFailure('flutter build failed (exit code $code).');
    }
    if (!ReleaseBuild.platforms.contains(platform)) {
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
}

/// `just game check [release-imports] [release-build] [formats]`: what
/// `just check` runs for the game (release-imports and formats), and the
/// check of a release build.
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
      final found = project.editorReachableFrom(game);
      result['release-imports'] = {'entry': game, 'reachable': found};
      if (found.isEmpty) {
        output.line('ok  No editor code is reachable from $game.');
      } else {
        failed = true;
        output.line('x   Editor code is reachable from $game:');
        for (final f in found) {
          output.line('      $f');
        }
      }
    }

    if (want.contains('release-build')) {
      final platform = platformOption ?? _desktop();
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
