/// The Just Game Engine's commands for `just` (just_core_cli), and the
/// release toolkit behind them.
///
/// **On every platform, the web included (JavaScript and WebAssembly):**
/// - [GameSet]: the engine's packages, at versions that work together, the
///   Flutter and Dart they need, and a pubspec moved onto them
///   ([GameSet.bump]).
/// - [GameTemplate]: a new game's files; [GameEntries]: where a game and
///   its editor start.
/// - [ReleaseRules], [ReleaseImports] and [ReleaseBuild]: proving that the
///   editor never ships — what must not, the imports a source names (and
///   [ReleaseImportsUnchecked], a walk that could not look), and the check
///   of a release build's files ([ReleaseBuildFiles]).
/// - [FormatsCheck]: the saved files' formats, and their migration.
///
/// **Where `dart:io` is (Windows, macOS, Linux, Android, iOS)**, the
/// library also exports the commands — `GameCommand`:
/// `just game run|build|check|scene|doctor|upgrade|migrate|mcp`, and the
/// hooks `just` runs (`game init` when `just create` makes a game,
/// `game link` for `just dev link|unlink`) — `MigrationSafety`, and the
/// `ProjectGame` extension, which reads a game on disk for the checks:
/// `releaseRules()`, `editorReachableFrom(entry)`,
/// `checkReleaseBuild(platform)`, `checkFormats()`, `editorIsOpen()` (the
/// heartbeat the editor writes, read as just_game_engine_formats'
/// `EditorHeartbeat` says). The `JustProject` it extends (from
/// `package:just_core_cli/project.dart`) is exported with it.
///
/// The just_core_cli types these take and give are exported too:
/// [JustProjectFile], [ProjectNames], [ToolSet], [SetPackage],
/// [PackageSource] and [Version].
library;

export 'package:just_core_cli/just_core_cli.dart'
    show
        JustProjectFile,
        PackageSource,
        ProjectNames,
        SetPackage,
        ToolSet,
        Version;

export 'src/game/game.dart';
export 'src/release/release.dart';
// What reads a disk and runs programs, where there is a machine; nothing
// more on the web. The native barrels are the defaults, so the analyzer and
// dartdoc see them.
export 'src/commands/commands.dart' if (dart.library.js_interop) 'src/web.dart';
export 'src/project/project.dart' if (dart.library.js_interop) 'src/web.dart';
