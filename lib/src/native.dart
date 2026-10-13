/// The part of `package:just_game_engine_cli/just_game_engine_cli.dart`
/// that needs a real machine — files, processes, a terminal: the commands,
/// and the `GameProject` extension that reads a game on disk. The library
/// exports it everywhere but the web (Windows, macOS, Linux, Android, iOS:
/// where `dart:io` is); on the web — where `dart.library.js_interop` is,
/// with JavaScript or WebAssembly — it exports `web.dart` instead.
library;

export 'package:just_core_cli/project.dart' show JustProject;

export 'commands/game_command.dart';
export 'commands/migration_safety.dart';
export 'project/game_project.dart';
