// `just game`: the plugin's manifest and its commands.

@TestOn('vm')
library;

import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:test/test.dart';

void main() {
  test("the manifest's hooks are commands the plugin has", () async {
    final manifest = PluginManifest.parse(
      File('just_plugin.json').readAsStringSync(),
    );
    expect(manifest.commands.keys, ['game']);
    final game = GameCommand();
    for (final hook in [
      'create',
      'doctor',
      'check',
      'upgrade',
      'migrate',
      'link',
    ]) {
      final words = manifest.hooks[hook]!.split(' ');
      expect(words.first, 'game', reason: hook);
      expect(game.subcommands.keys, contains(words[1]), reason: hook);
    }
  });
}
