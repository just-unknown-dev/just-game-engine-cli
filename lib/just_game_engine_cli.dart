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
///   editor never ships — what must not, the imports a source names, and
///   the check of a release build's files ([ReleaseBuildFiles]).
/// - [FormatsCheck]: the saved files' formats, and their migration.
/// - [EditorPresence]: the editor's heartbeat, which says it has a project
///   open.
///
/// **Where `dart:io` is (Windows, macOS, Linux, Android, iOS)**, the
/// library also exports the commands — `GameCommand`:
/// `just game run|build|check|scene|doctor|upgrade|migrate`, and the hooks
/// `just` runs (`game init` when `just create` makes a game, `game link`
/// for `just dev link|unlink`) — `MigrationSafety`, and the `GameProject`
/// extension, which reads a game on disk for the checks:
/// `releaseRules()`, `editorReachableFrom(entry)`,
/// `checkReleaseBuild(platform)`, `checkFormats()`, `editorIsOpen()`. The
/// `JustProject` it extends (from `package:just_core_cli/project.dart`) is
/// exported with it.
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

export 'src/create/game_set.dart';
export 'src/create/game_template.dart';
export 'src/project/editor_presence.dart';
export 'src/project/game_entries.dart';
export 'src/release/formats_check.dart';
export 'src/release/release_build.dart';
export 'src/release/release_imports.dart';
export 'src/release/release_rules.dart';
// The commands where there is a machine; nothing more on the web. The
// native barrel is the default, so the analyzer and dartdoc see it.
export 'src/native.dart' if (dart.library.js_interop) 'src/web.dart';
