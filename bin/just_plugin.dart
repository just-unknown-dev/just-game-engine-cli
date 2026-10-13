// The Just Game Engine's commands for `just`: `just game ...`. Not a tool
// of its own: `just` runs this with `dart run just_game_engine_cli:just_plugin`.

import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_game_engine_cli/just_game_engine_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runJustPlugin(arguments, [GameCommand()]);
}
