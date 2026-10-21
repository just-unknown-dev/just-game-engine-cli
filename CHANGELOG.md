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
