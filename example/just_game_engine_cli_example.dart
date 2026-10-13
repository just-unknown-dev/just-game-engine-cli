// Proving from a game's source that its editor can't ship — what
// `just game check release-imports` does — from a script or a test.
//
//     dart run example/just_game_engine_cli_example.dart [game folder]
//
// The rules come from the project: the editor's own packages and the tools,
// plus every installed Asset Store item's editor-only libraries.

import 'dart:io';

import 'package:just_game_engine_cli/just_game_engine_cli.dart';

void main(List<String> args) {
  final project = JustProject(args.isEmpty ? Directory.current.path : args[0]);
  final rules = project.releaseRules();
  stdout.writeln('Never in a release: ${rules.forbidden.join(', ')}');

  const entry = GameEntries.defaultGame;
  final reachable = project.editorReachableFrom(entry, rules: rules);
  if (reachable.isEmpty) {
    stdout.writeln('OK: no editor code is reachable from $entry.');
    return;
  }
  stderr.writeln('Editor code is reachable from $entry:');
  for (final trail in reachable) {
    stderr.writeln('  $trail');
  }
  exitCode = 1;
}
