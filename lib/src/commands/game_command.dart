/// `just game …`: the Just Game Engine's commands.
library;

import 'package:just_core_cli/just_core_cli.dart';

import 'doctor_command.dart';
import 'init_command.dart';
import 'link_command.dart';
import 'migrate_command.dart';
import 'run_build_check.dart';
import 'scene_command.dart';
import 'upgrade_command.dart';

/// `just game`: run and build the game, check that a release holds no
/// editor, manage its scenes, move the engine's packages and migrate its
/// saved files — plus the hooks `just` runs: `game init` (when
/// `just create` makes a game), `game check`, `game doctor`,
/// `game upgrade`, `game migrate` and `game link` (`just dev link`).
///
/// The plugin's entry point (`bin/just_plugin.dart`) runs it:
///
/// ```dart
/// exitCode = await runJustPlugin(arguments, [GameCommand()]);
/// ```
final class GameCommand extends JustCommand {
  /// The command and all its subcommands.
  GameCommand() {
    for (final c in <JustCommand>[
      GameRunCommand(),
      GameBuildCommand(),
      GameCheckCommand(),
      SceneCommand(),
      GameDoctorCommand(),
      GameUpgradeCommand(),
      GameMigrateCommand(),
      GameInitCommand(),
      GameLinkCommand(),
    ]) {
      addSubcommand(c);
    }
  }

  @override
  String get name => 'game';

  @override
  String get description =>
      'Run and build the game, check that releases hold no editor, manage '
      'its scenes and migrate its saved files.';
}
