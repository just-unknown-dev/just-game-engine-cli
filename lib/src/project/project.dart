/// A game on disk, where `dart:io` is (Windows, macOS, Linux, Android,
/// iOS): what the game's checks read from a project ([ProjectGame], an
/// extension on just_core_cli's [JustProject], exported with it), and when
/// old saved files may be rewritten ([MigrationSafety]).
library;

export 'package:just_core_cli/project.dart' show JustProject;

export 'migration_safety.dart';
export 'project_game.dart';
