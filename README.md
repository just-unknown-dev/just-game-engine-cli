# Just Game Engine CLI

The [Just Game Engine](https://engine.justunknown.com/)'s commands for `just`, the Just ecosystem's command-line tool ([just_core_cli](https://pub.dev/packages/just_core_cli)): run the game and its editor, build releases that provably hold no editor, manage the levels, keep the engine's packages on versions that work together, and keep the saved files in the current formats.

It is a `just` plugin, not a tool of its own, and it is only for the Just Game Engine and its editor: everything the engine needs from `just` is here, and just_core_cli stays a general core. Every game made with `just create` has it as a dev dependency, and `just` runs it at the version the project resolved. It owns the engine's versions — `GameSet`: the engine's packages, the Asset Store and editors, and the Flutter and Dart they need — while just_core_cli's tool set holds only just_core_cli and this package.

## Use

```text
just create my_game                       # a new game: just_core_cli asks this package to fill it in
cd my_game
just game run --editor                    # the game with the level editor (desktop, debug)
just game run                             # the game; anything after -- goes to flutter run
just game build windows                   # a release build, then a check that it holds no editor

just game scene new cave --after level_01 # a level, as the editor's New Scene writes it
just game scene list | rename | delete | order | migrate | validate

just game check                           # no editor reachable from the game; saved formats readable
just game check release-build --platform web
just game doctor                          # the editor kept out, SDK floors, engine versions, store links
just game upgrade --check                 # what the engine's packages would move to (just upgrade runs it)
just game migrate                         # old scenes, timelines and animator graphs rewritten
```

`just check`, `just doctor`, `just upgrade` and `just dev link|unlink` run the matching `game` commands for you: they are this plugin's hooks. `just help game build` shows a command's own help.

Every command takes `--json` (one JSON document on stdout, messages on stderr), `--yes`, `--verbose` and `--project <folder>`, and exits 0 (done), 1 (failed, nothing left half done) or 2 (called wrongly). `game run` hands the terminal to `flutter run` and exits with its code.

## The hooks

`just_plugin.json` gives `just` six hooks:

| Hook | Command | When |
|---|---|---|
| `create` | `game init` (hidden) | `just create` made a Flutter project: lay the game template over it on the `GameSet` (keeping just_core_cli and this package in its dev dependencies), add the editor through the Asset Store, switch Flutter GPU on for a 3D game |
| `check` | `game check` | `just check`: release imports and saved formats |
| `doctor` | `game doctor` | `just doctor`: the editor kept out of releases, git ignores, the macOS entitlement, Flutter and Dart against the engine's floors, the engine's packages against what resolved, store items linked to missing checkouts |
| `upgrade` | `game upgrade` | `just upgrade`, inside its transaction: one-line bumps of the engine's packages in `pubspec.yaml` to the `GameSet` (a package already as new as the set, or newer, stays), no `pub get` (`just upgrade` fetches); `--check` (when the tools stay) says what would move |
| `migrate` | `game migrate` | `just upgrade` runs it with `--check` before it changes anything and again with the new packages before it commits, then for real; `just upgrade -- --engine-only` passes the flag on |
| `link` | `game link` (hidden) | after `just dev link`: register the Asset Store items among the checkouts (`store link`); before `just dev unlink` (`--unlink --check`): refuse while the pubspec asks pub.dev for a package only git or the store supplies |

`game migrate --check` changes nothing: it fails, saying why, when a migration could not run now — while the editor has the project open, or when old files would be rewritten past a kit that has migration rules of its own (`--engine-only` goes ahead anyway). `--force` goes ahead though the editor is open. Without `--check`, an open editor stops it only when there are files to rewrite; with `--json`, its result's `migrated` lists what it rewrote.

Every change these commands make goes through just_core_cli's transactions with the editor's trash (`trashRoot: '.editor_trash'`, `GameTemplate.editorTrash`): what a scene change or a migration replaces is restorable from the editor, as before.

The Asset Store is called like any plugin, under just_core_cli's trust rule: from a local checkout or the ecosystem's repositories it runs; from pub.dev it runs once just_core_cli lists its name as claimed there (`PluginTrust.onPubDev`); from anywhere else only once allowed in `just.json` or your user `plugins.json`, or when you say yes in a terminal.

## As a library

`package:just_game_engine_cli/just_game_engine_cli.dart` holds the toolkit the commands use, for a game's own scripts and tests, and for tools on any platform, the web included. A script that reads a game on disk (where `dart:io` is):

```dart
import 'package:just_game_engine_cli/just_game_engine_cli.dart';

void main() {
  final project = JustProject('.');
  final rules = project.releaseRules(); // the editor's packages + each store item's
  final reachable = project.editorReachableFrom('lib/main.dart', rules: rules);
  if (reachable.isNotEmpty) throw StateError('The editor would ship: $reachable');
}
```

**On every platform, the web included (JavaScript and WebAssembly)**, the checks work on text:

- `GameSet`: the engine's packages at versions that work together, and the Flutter and Dart they need; `bump` moves a pubspec onto them, and never moves a package that is ahead of the set back.
- `GameTemplate` and `GameEntries`: a new game's files, and where a game and its editor start.
- `ReleaseRules`, `ReleaseImports` and `ReleaseBuild`: what must never reach a release, the imports a source names, and the check of a release build's files (`ReleaseBuildFiles`: `windows`, `macos`, `linux` and `web`, whose JavaScript is checked, and its WebAssembly too when a `--wasm` build loads it).
- `FormatsCheck`: a saved file against the formats this engine reads, and its migration.
- `EditorPresence`: the editor's heartbeat, which says it has a project open.

The just_core_cli types these take (`JustProjectFile`, `ProjectNames`, `ToolSet`, `SetPackage`, `PackageSource`, `Version`) come with the library.

**Where `dart:io` is (Windows, macOS, Linux, Android, iOS)**, the library also reads a game on disk and runs the commands:

- `GameProject`, an extension on `JustProject`: `releaseRules()`, `editorReachableFrom(entry)`, `checkReleaseBuild(platform)`, `devOnlyPlugins(platform)`, `checkFormats()` and `editorIsOpen()`.
- `GameCommand` (the commands themselves) and `MigrationSafety`.

The saved formats themselves are [just_game_engine_formats](https://pub.dev/packages/just_game_engine_formats)'; this package only calls them.
