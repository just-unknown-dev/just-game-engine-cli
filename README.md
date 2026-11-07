# Just Game Engine CLI

The [Just Game Engine](https://engine.justunknown.com/)'s commands for `just`, the Just ecosystem's command-line tool ([just_core_cli](https://pub.dev/packages/just_core_cli)): run the game and its editor, build releases that provably hold no editor, manage the levels, keep the engine's packages on versions that work together, and keep the saved files in the current formats.

It is a `just` plugin, not a tool of its own, and it is only for the Just Game Engine and its editor: everything the engine needs from `just` is here, and just_core_cli stays a general core. Every game made with `just create` has it as a dev dependency, and `just` runs it at the version the project resolved. It owns the engine's versions — `GameSet`: the engine's packages, the Asset Store and editors, and the Flutter and Dart they need — while just_core_cli's tool set holds only just_core_cli and this package.

Games are pinned to one Flutter version, **3.47.9**: the engine draws 3D with Flutter GPU, a preview whose API changes between Flutter versions. The version is in this package's pubspec (`just: flutter: 3.47.9`), where `just create` reads it to make the game with that Flutter and write it into the game's `just.json`; `just upgrade` moves it with this package, and every `just` command uses it (`just flutter …` too), installing it when you say so.

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

just game mcp                             # for an AI assistant: the engine's docs and API over MCP
```

`just game mcp` is an MCP server on stdin and stdout, which an AI assistant starts (a new game's `.mcp.json` and `.vscode/mcp.json` say how). Its tools only read: `search_docs`, `read_doc` and `get_api` serve the guides, notes and public API of the engine packages the game resolved, at those versions; `project_info`, `list_scenes`, `validate_scenes` and `check_game` run the commands above in-process.

`just check`, `just doctor`, `just upgrade` and `just dev link|unlink` run the matching `game` commands for you: they are this plugin's hooks. `just help game build` shows a command's own help.

Every command takes `--json` (one JSON document on stdout, messages on stderr), `--yes`, `--verbose` and `--project <folder>`, and exits 0 (done), 1 (failed, nothing left half done) or 2 (called wrongly). `game run` hands the terminal to `flutter run` and exits with its code.

## The hooks

`just_plugin.json` gives `just` six hooks:

| Hook | Command | When |
|---|---|---|
| `create` | `game init` (hidden) | `just create` made a Flutter project: lay the game template over it on the `GameSet` (keeping just_core_cli and this package in its dev dependencies, and the editor from pub.dev), lay a store `--template` over it, switch Flutter GPU on for a 3D game |
| `check` | `game check` | `just check`: release imports and saved formats |
| `doctor` | `game doctor` | `just doctor`: the editor kept out of releases, git ignores, the macOS entitlement, Flutter and Dart against the versions the engine works with, the engine's packages against what resolved, store items linked to missing checkouts |
| `upgrade` | `game upgrade` | `just upgrade`, inside its transaction: one-line bumps of the engine's packages in `pubspec.yaml` to the `GameSet` (a package already as new as the set, or newer, stays), no `pub get` (`just upgrade` fetches); `--check` (when the tools stay) says what would move |
| `migrate` | `game migrate` | `just upgrade` runs it with `--check` before it changes anything and again with the new packages before it commits, then for real; `just upgrade -- --engine-only` passes the flag on |
| `link` | `game link` (hidden) | after `just dev link`: register the Asset Store items among the checkouts (`store link`); before `just dev unlink` (`--unlink --check`): refuse while the pubspec asks pub.dev for a package only git or the store supplies |

`game migrate --check` changes nothing: it fails, saying why, when a migration could not run now — while the editor has the project open, or when old files would be rewritten past a kit that has migration rules of its own (`--engine-only` goes ahead anyway). `--force` goes ahead though the editor is open. Without `--check`, an open editor stops it only when there are files to rewrite; with `--json`, its result's `migrated` lists what it rewrote.

The commands that change a game's saved files — `game scene new|rename|delete|order|migrate` and `game migrate` — go through just_core_cli's transactions, under the project lock, with the editor's trash (`trashRoot: '.editor_trash'`, `GameTemplate.editorTrash`): all or nothing, and what they replace is restorable from the editor. Each rewritten file is written as the editor writes it and ends as it did (its line endings and final newline). `game init` and `game upgrade` write with plain atomic writes instead: they run inside `just create` and `just upgrade`, whose own transactions hold them (on its own, `game upgrade` changes one file, `pubspec.yaml`).

`game check` (and `game build`, before it builds) walks the imports from the game's entry point, into the packages that can reach editor code (`.dart_tool/package_graph.json` says which). A walk that could not look — the entry point is not there, the packages were never fetched, an import names a package pub did not resolve or a file that is not there — fails, saying why, rather than report no editor code without having looked.

The Asset Store is called like any plugin, under just_core_cli's trust rule: from a local checkout or the ecosystem's repositories it runs, and from pub.dev, where the game set gets it, too: just_core_cli lists its name as claimed there (`PluginTrust.onPubDev`, from just_core_cli 0.1.1); from anywhere else only once allowed in `just.json` or your user `plugins.json`, or when you say yes in a terminal.

## As a library

`package:just_game_engine_cli/just_game_engine_cli.dart` holds the toolkit the commands use, for a game's own scripts and tests, and for tools on any platform, the web included. A script that reads a game on disk (where `dart:io` is):

```dart
import 'package:just_game_engine_cli/just_game_engine_cli.dart';

void main() {
  final project = JustProject('.');
  final rules = project.releaseRules(); // the editor's packages + each store item's
  // Throws ReleaseImportsUnchecked when it could not look everywhere.
  final reachable = project.editorReachableFrom('lib/main.dart', rules: rules);
  if (reachable.isNotEmpty) throw StateError('The editor would ship: $reachable');
}
```

**On every platform, the web included (JavaScript and WebAssembly)**, the checks work on text:

- `GameSet`: the engine's packages at versions that work together, and the Flutter and Dart they need; `bump` moves a pubspec onto them, and never moves a package that is ahead of the set back.
- `GameTemplate` and `GameEntries`: a new game's files, and where a game and its editor start.
- `ReleaseRules`, `ReleaseImports` and `ReleaseBuild`: what must never reach a release, the imports a source names (and `ReleaseImportsUnchecked`, a walk that could not look), and the check of a release build's files (`ReleaseBuildFiles`: `windows`, `macos`, `linux` and `web`, whose JavaScript is checked, and its WebAssembly too when a `--wasm` build loads it).
- `FormatsCheck`: a saved file against the formats this engine reads, and its migration (`migrated`, `endingAs`: rewritten as the editor writes it, ending as the file did).

The just_core_cli types these take (`JustProjectFile`, `ProjectNames`, `ToolSet`, `SetPackage`, `PackageSource`, `Version`) come with the library.

**Where `dart:io` is (Windows, macOS, Linux, Android, iOS)**, the library also reads a game on disk and runs the commands:

- `ProjectGame`, an extension on `JustProject`: `releaseRules()`, `editorReachableFrom(entry)`, `checkReleaseBuild(platform)`, `devOnlyPlugins(platform)`, `checkFormats()` and `editorIsOpen()` (whether the editor's heartbeat, just_game_engine_formats' `EditorHeartbeat`, is fresh).
- `GameCommand` (the commands themselves; its subcommands are the package's own) and `MigrationSafety`.

The saved formats themselves are [just_game_engine_formats](https://pub.dev/packages/just_game_engine_formats)'; this package only calls them.

## Versions and publishing

Each release carries the engine's versions as its `GameSet` (0.2.1: set 2026.11, with just_core_cli's `ToolSet` 2026.11). Publish this package **last**, after every package its `GameSet` names (the engine and its packages, just_game_engine_formats, the Asset Store, the editor and its core, and the kits, which are tagged in their repositories) and after just_core_cli, whose `ToolSet` names this version: a game made with it fetches them all.
