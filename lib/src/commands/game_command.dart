/// `just game …`: the Just Game Engine's commands.
library;

import 'package:just_core_cli/just_core_cli.dart';

import 'game_build_command.dart';
import 'game_check_command.dart';
import 'game_doctor_command.dart';
import 'game_init_command.dart';
import 'game_link_command.dart';
import 'game_mcp_command.dart';
import 'game_migrate_command.dart';
import 'game_run_command.dart';
import 'game_scene_command.dart';
import 'game_upgrade_command.dart';

/// `just game`: run and build the game, check that a release holds no
/// editor, manage its scenes, move the engine's packages and migrate its
/// saved files, serve the engine to an AI assistant (`game mcp`) — plus the
/// hooks `just` runs: `game init` (when `just create` makes a game),
/// `game check`, `game doctor`, `game upgrade`, `game migrate` and
/// `game link` (`just dev link`).
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
      GameSceneCommand(),
      GameDoctorCommand(),
      GameUpgradeCommand(),
      GameMigrateCommand(),
      // It runs `just game` commands in-process, on a command of their own.
      GameMcpCommand(GameCommand.new),
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
