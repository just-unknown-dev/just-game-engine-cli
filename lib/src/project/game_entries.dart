/// A game's entry points.
library;

import 'package:just_core_cli/just_core_cli.dart';

/// Where a game starts, and where its editor does: `just.json`'s
/// `entry.game` and `entry.editor`, else [defaultGame] and
/// [defaultEditor].
abstract final class GameEntries {
  /// The `entry` key for the game.
  static const String gameKey = 'game';

  /// The `entry` key for the game with the editor over it.
  static const String editorKey = 'editor';

  /// Where the game starts, unless `entry.game` says otherwise.
  static const String defaultGame = 'lib/main.dart';

  /// Where the editor starts, unless `entry.editor` says otherwise.
  static const String defaultEditor = 'lib/main_editor.dart';

  /// The game's entry point in [file]: the one that ships.
  static String game(JustProjectFile file) =>
      file.entries[gameKey] ?? defaultGame;

  /// The editor's entry point in [file]: the game with the editor over it
  /// in a debug build, and the game alone in any other.
  static String editor(JustProjectFile file) =>
      file.entries[editorKey] ?? defaultEditor;
}
