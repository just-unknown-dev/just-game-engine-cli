/// `just game run`.
library;

import 'package:just_core_cli/just_core_cli.dart';
import 'package:meta/meta.dart';

import '../game/game.dart';
import 'flutter_target.dart';

/// `just game run [--editor] [flutter run options]`: the game, or the game
/// with the editor over it.
@internal
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
    final device =
        argResults!.option('device') ?? (editor ? desktopPlatform() : null);
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
      flutterFor(this, project).flutter,
      args,
      workingDirectory: project.root,
    );
  }
}
