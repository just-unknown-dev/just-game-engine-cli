## 0.2.0

**Publish it last**: after every version its game set names (the engine and its packages, just_game_engine_formats 0.3.0, the Asset Store 0.3.0, the editor 0.1.0-dev.3 and its core 0.1.0-dev.2, and the kits, tagged in their repositories) and after just_core_cli 0.2.0, whose tool set 2026.11 names this version. A game made with it fetches them all.

Requires just_core_cli ^0.2.0 and just_game_engine_formats ^0.3.0; depends on dart_mcp ^0.5.2 and meta ^1.15.0.

### Breaking

- The extension that reads a game on disk is `ProjectGame` (was `GameProject`), by the naming rule for extensions. Its members are unchanged: `releaseRules()`, `editorReachableFrom()`, `checkReleaseBuild()`, `devOnlyPlugins()`, `checkFormats()`, `editorIsOpen()`.
- `JustProject.editorReachableFrom` throws `ReleaseImportsUnchecked` when it could not look everywhere it had to: the entry point is not there, the project's packages were never fetched, or an import names a package pub did not resolve or a file that is not there. It used to return no offenders, so `just game check` said "No editor code is reachable" for a typo in `just.json`'s `entry.game`, or for a game whose packages weren't fetched. A script that calls it catches the exception, or fails.
- The commands' subcommands (`GameRunCommand`, `GameBuildCommand`, `GameCheckCommand`, `GameSceneCommand` — was `SceneCommand` —, `GameDoctorCommand`, `GameUpgradeCommand`, `GameMigrateCommand`, `GameMcpCommand`, `GameInitCommand`, `GameLinkCommand`) and the MCP server's classes are `@internal`: the public API is `GameCommand`. The in-process runner's typedefs are `InProcessJust` and `InProcessRun` (were `JustRunner`, which clashed with just_core_cli's command runner, and `JustRun`).
- `lib/src/` is laid out by feature, one barrel per folder: `game/` and `release/` (on every platform), `project/`, `mcp/` and `commands/` (where `dart:io` is). `src/create/templates.g.dart` is `src/game/bundled_templates.g.dart` (and `src/native.dart` is gone: see Removed). The public library's exports are unchanged apart from the renames.
- `EditorPresence` is gone: the editor's heartbeat is just_game_engine_formats' `EditorHeartbeat`, which the editor writes through too (`EditorPresence.path` → `EditorHeartbeat.path`, `beat` → `interval`, `stale` → `staleAfter`, `isFresh(touched, now:)` → `!EditorHeartbeat.decode(text, modified: touched).isStale(now)`). `editorIsOpen()` reads the beat the file holds, and a file without one (an editor before 0.1.0-dev.3, which wrote its process ID) by when it was last written, as before. The two packages kept the path and timings in step by hand.
- **The game set is 2026.11** (with just_core_cli's tool set 2026.11): just_game_engine ^2.0.0-dev.4, just_game_engine_formats ^0.3.0, just_physics_engine ^2.0.0, just_box_2d ^0.2.0, just_jolt ^0.2.0, just_inputs ^0.2.0, just_tiled ^0.5.0, just_dart ^0.3.0, just_graphics_engine ^0.2.0-dev.1, just_deflate ^0.1.0, just_audio_engine ^2.0.0, just_asset_store ^0.3.0, just_game_engine_editor ^0.1.0-dev.3, just_editor_core ^0.1.0-dev.2, just_world_builder_kit and just_third_person_kit ^0.2.0-beta.1. `game upgrade` (and `just upgrade`) moves a game onto it. It no longer has just_material_editor: the package is retired (it was an empty placeholder; materials are the editor's own), so `game init --local` no longer links a checkout of it, and `game doctor` and `game upgrade` no longer check or move its version.

### Added

- **`just game mcp`**: an MCP server for AI assistants (Claude Code, VS Code, Cursor, …), on stdin and stdout. It serves the engine as the game resolved it, so an assistant stops guessing 1.x or Flame APIs:
  - `search_docs`: keyword search over just_game_engine's guides (`doc/guides/`, from the version that ships them), the packages' README, MIGRATION and CHANGELOG, and their public API.
  - `read_doc`: a guide or note, whole or one section. `get_api`: a type or member's signature, doc comment, import, constructors, members and subtypes, with what replaces a deprecated one, read from the packages' source (export chains followed across packages).
  - `project_info`, `list_scenes`, `validate_scenes` and `check_game` (`game doctor` and `game check`) run in-process, their output kept off the MCP stream.
  - Every tool only reads. The server's instructions give the engine's versions and the rules that trip people up.
- A new game has `AGENTS.md` (how it is built, its commands, those rules), a `CLAUDE.md` that points to it, and `.mcp.json` and `.vscode/mcp.json`, which start `just game mcp`.
- `ReleaseImportsUnchecked` (its `entry`, `reasons`, the `reachable` trails found anyway, and a `message`), and `FormatsCheck.endingAs`, new text that ends as a file did.
- `game check --json`'s `release-imports` result has `unchecked`, the reasons a walk could not look.

### Changed

- **The release-imports walk reads only packages that can reach editor code**: those that are, or depend on (`.dart_tool/package_graph.json`), a package the release rules name, or the project itself. Flutter and the rest are never read: about 250 ms on the platformer template, where it read 2,294 files in 1.4–1.8 s warm (5 s cold). Without a package graph every package is walked, as before.
- `game build --editor-entry` no longer walks the editor's entry point, whose result it ignored: its build is the proof. Before building, `game build` refuses an entry point that is not there; a walk that could not look (the packages not fetched yet) is a warning, and after the build the build is checked — or, for a platform whose build the check can't read (`apk`, `ios`…), the source is walked again, and the command fails if it still can't be.
- `game scene migrate` writes any scene whose migration changed it, a current-format one included (a timeline it keeps inline brought up to date, now that the formats rename and update at any version); a scene nothing changes is left as it is, byte for byte. The kits' rules (`MigrationSafety`) are asked only when an older scene is rewritten.
- `game doctor` judges the entry point's imports by the game's release rules, as `game check` does (`package:just_editor_core/…` and `package:just_asset_store/…` count too, and a game file named like `editor_theme.dart` doesn't), names the imports it found, reads `pubspec.yaml`'s dependencies however they are indented or written, and asks git whether the editor's folders are ignored (`/.editor_trash/`, `.editor_trash` or an ignore further up count; without git it reads `.gitignore` as git would).
- `check release-build` looks for the engine's renamed 3-D physics system (`Physics3DSystem`) in a 2-D game's release.
- The `empty` template draws its stand-in player with `Rectangle2DComponent`, the engine's new name for `RectangleComponent`.
- A new game's `AGENTS.md` and the MCP server's rules say `Engine.getSystem` is gone (it was deprecated); the `empty` template's boot lists animators and timelines among the engine's standard systems.
- `game init --local` finds checkouts with just_core_cli's `DevLinks.scanAll` (the same folder named two ways is one checkout), and reads the pubspec's name with `PubspecFields`; the MCP server reads versions and pub-cache packages with just_core_cli's `ResolvedPackage`.

### Fixed

- **The release-imports check no longer passes without having looked** (see Breaking): `game check` fails with "The editor-import check of lib/main.dart proves nothing: …", and a forbidden import counts whether or not pub resolved its package.
- **A declined question fails with a reason**: answering no to `game scene delete`, `game migrate` or `game upgrade` exits 1 with "Nothing was changed: … was declined." (and `--json`'s `error` says so); it said nothing.
- **`game scene migrate`, `game scene rename` and `game migrate` write a file the same way**: as the editor writes it, ending as it did — CRLF stays CRLF (a Windows checkout with `core.autocrlf`), and a final newline stays. `scene` dropped the final newline, and every migrated file came out LF.
- `MigrationSafety` (and so `game migrate`, `game migrate --check` and `just upgrade`) no longer stops with a `FileSystemException` at a package whose `just_store.json` isn't UTF-8 or can't be read: it is no kit, as one that isn't JSON.
- `just game mcp` no longer ends when its background read of the engine's API fails: a folder it can't list or a file its scanner trips on is left out and named, `get_api` and `search_docs` say what is missing, and the rest is served.

### Removed

- `src/native.dart` (the public library exports the `commands/` and `project/` barrels instead), and the private copies of just_core_cli's pubspec readers and checkout scan.

## 0.1.4

- **`just create` works again.** The game set took just_game_engine_editor and just_editor_core from the Asset Store, but they are on pub.dev and the store doesn't list them, so `game init` failed at `just store install just_game_engine_editor` ("not in any of your sources") and the new project was removed. They now come from pub.dev: a new game lists the editor in its `dev_dependencies`, and the store runs only for a `--template` (and `--local`'s `store link`). Only plugins (kits and editor tools) still come from the store.
- The game set asks for just_physics_engine ^1.4.1, the version on pub.dev and the one the engine needs. ^1.5.0 doesn't exist, so `just doctor` warned about it in every new game.

## 0.1.3

- **The Asset Store is part of the editor** from just_game_engine_editor 0.1.0-dev.2, so the game set 2026.10 asks for the editor at ^0.1.0-dev.2 and no longer has just_asset_store_editor. `game init` (`just create`) installs the editor alone, and a new game's `EditorWiring.modules` lists only the store items' modules (`storeModules()`).
- The game set asks for just_game_engine ^2.0.0-dev.3, whose animators leave a scene's saved animation fields as they were authored (the third-person template reads the new playing values).
- The game set asks for just_asset_store ^0.1.1, which installs editor tools and kits into `plugins/{category}/{name}/` and content into `packages/{category}/{name}/`.
- The release checks look for the editor's store module by its new names (`BuiltInAssetStoreModule`, `asset_store.open`); just_asset_store stays forbidden in a release.
- `game init` takes `--local` once for each folder of checkouts, as just_core_cli 0.1.2's `just create --local` passes them (say `packages/` and `plugins/`), and registers the store items of all of them; a package checked out in two of them stops it.

## 0.1.2

- **Needs just_core_cli ^0.1.1**, which trusts just_asset_store from pub.dev (`PluginTrust.onPubDev`). Game set 2026.10 takes the store from pub.dev, and just_core_cli 0.1.0 trusted it only from a checkout or its git repository, so `game init` (`just create`) refused to run it under `--yes` and asked about it in a terminal. Now it runs without asking, as it did from its git tag.
- just_asset_store is a dev dependency again, as it was before 0.1.1: the store is a tool, and a game never ships it. `game init --local` registers its checkout among the store items again.
- `game link --unlink --check` names what each stranded package needs: its git source, or, for a store item, `just store install <id>`. It no longer tells you to add just_asset_store as a git dependency with no URL.

## 0.1.1

- The game set 2026.10 moves to just_game_engine_formats ^0.2.0, just_physics_engine ^1.5.0, just_graphics_engine ^0.1.0-dev.2, just_game_engine_editor and just_editor_core ^0.1.0-dev.1 (their first releases), just_third_person_kit ^0.1.0-dev.1, and has just_world_builder_kit ^0.1.0-dev and just_material_editor ^0.1.0-dev.1 (its first release). just_graphics_editor leaves the set: editing 3D graphics is the editor's own.
- `game scene validate` accepts entries that place a prefab.

## 0.1.0

- **`just_editor_core`**, the editor's module contract split out of `just_game_engine_editor`, is in the game set (it comes with the editor and the kits) and editor-only for a release: nothing a release builds may import it.

The first release: the Just Game Engine's commands for `just` (just_core_cli 0.1.0), as a plugin every game has in its dev dependencies.

- **Running and shipping:** `game run [--editor]`; `game build <platform> [--editor-entry]`, then a check that the release build holds no editor (and, in a 2D game, no 3D physics), on the web in the JavaScript and, from a `--wasm` build, the WebAssembly; `game check [release-imports|release-build|formats]`.
- **Scenes:** `game scene list|new|rename|delete|order|migrate|validate`, written as the editor writes them, and never while the editor has the project open.
- **The engine's versions:** `GameSet` holds the engine's packages (with the Asset Store from git and the editors from the store) and the Flutter and Dart they need; `game init` starts a game on it, `game doctor` checks against it, and `game upgrade [--check]` moves the pubspec's one-line constraints to it (never a package that is ahead of it back) — the `upgrade` hook of `just upgrade`, which fetches the packages in its transaction.
- **Setup and upgrades:** `game doctor` (the editor kept to debug builds and out of the game's imports and dependencies, git ignores, the macOS network entitlement); `game migrate [--check] [--engine-only] [--force]` rewrites old scenes, timelines and animator graphs in one transaction, and only those: a file of another kind is never read as one of them. An open editor stops it only when there is something to rewrite; `--check` answers `just upgrade` before it changes anything.
- **Hooks:** `create` (`game init`: the game template, the first level, the editor from the Asset Store, Flutter GPU for a 3D game), `check`, `doctor`, `upgrade`, `migrate` and `link` (`game link`: store items registered after `just dev link`; `just dev unlink` refused while only the links supply a package), which `just create`, `just check`, `just doctor`, `just upgrade` and `just dev link|unlink` run. `game doctor` also checks the SDK floors, the engine's versions and the store's links to checkouts.
- **The toolkit**, on every platform including the web (JavaScript and WebAssembly): `GameSet`, `GameTemplate`, `GameEntries`, `ReleaseRules`, `ReleaseImports`, `ReleaseBuild` (with `ReleaseBuildFiles`), `FormatsCheck` and `EditorPresence` work on text. Where `dart:io` is, the `GameProject` extension on `JustProject` reads a game on disk for them (`releaseRules()`, `editorReachableFrom()`, `checkReleaseBuild()`, `checkFormats()`, `editorIsOpen()`), and the commands run.
