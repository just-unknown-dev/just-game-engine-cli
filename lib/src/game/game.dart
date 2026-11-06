/// What a game is, as text, on every platform (the web included): the
/// engine's packages at versions that work together ([GameSet]), a new
/// game's files ([GameTemplate]), and where a game and its editor start
/// ([GameEntries]).
///
/// Nothing here reads a disk: no `dart:io`, no
/// `package:just_core_cli/project.dart`.
library;

export 'game_entries.dart';
export 'game_set.dart';
export 'game_template.dart';
