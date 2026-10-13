# Contributing to Just Game Engine CLI

Thank you for your interest in contributing to **just_game_engine_cli**, the Just Game Engine's commands for `just`. Bug fixes, features, tests and documentation are all welcome.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Reporting Bugs and Suggesting Features](#reporting-bugs-and-suggesting-features)
- [Development Setup](#development-setup)
- [Working Against Unpublished Dependencies](#working-against-unpublished-dependencies)
- [How the Package Fits Together](#how-the-package-fits-together)
- [Templates and the `tool/` Folder](#templates-and-the-tool-folder)
- [Running the Tests](#running-the-tests)
- [Coding Guidelines](#coding-guidelines)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Releasing](#releasing)
- [Commit Message Convention](#commit-message-convention)
- [License](#license)

---

## Code of Conduct

This project follows our [Code of Conduct](CODE_OF_CONDUCT.md). By taking part you agree to its terms. Please report unacceptable behaviour to the maintainers.

---

## Reporting Bugs and Suggesting Features

Before opening an issue, search the [existing issues](https://github.com/just-unknown-dev/just-game-engine-cli/issues) and check that the problem happens on the latest version.

A bug report should have:

- a clear title;
- the command you ran (`just game …`, or the `just create`, `just check`, `just doctor` or `just upgrade` that ran it as a hook), and what you expected instead of what happened. Run it again with `--verbose` and include the output; if a script hit the problem, include its `--json` output too;
- the output of `just --version`, `just doctor` and `flutter --version`, the version of just_game_engine_cli the project resolved (in its `pubspec.lock`), and your operating system and shell;
- for a command that changes a project: the project's `pubspec.yaml` and `just.json`, whether the failed command left anything changed, and whether a journal was left in `.dart_tool/just_core_cli/txn/`;
- for `game build` or `game check`: the platform and the full report.

Not every `just` bug is this package's. `just` itself — `create`'s generic steps, plugins, pinning, `dev link`, the project toolkit — is [just_core_cli](https://github.com/just-unknown-dev/just-core-cli/issues); `store`, `add` and `remove` are [just_asset_store](https://github.com/just-unknown-dev/just-asset-store/issues)'s. A scene, timeline or animator graph that comes out of a migration wrong belongs in [just_game_engine_formats](https://github.com/just-unknown-dev/just-game-engine-formats/issues): this package only calls it. The editor that `just game run --editor` starts is `just_game_engine_editor`.

For a feature, open an issue labelled **`enhancement`** that describes the problem it solves and how it should behave. The package's scope is a game's life outside the editor: making it (the `create` hook), running, building, checking and migrating it, and its scenes. A change to a command's `--json` output or exit codes, to `just_plugin.json`'s hooks, or to what `game init` writes into a new game reaches scripts, `just` and every new project, so open the issue first and agree the approach before you write it.

---

## Development Setup

| Tool | Minimum version |
|------|-----------------|
| Dart | 3.11.0 |
| Flutter | Not needed for the tests. `game run`, `game build` and `game init` find it on the `PATH` or through `FLUTTER_ROOT` |

```bash
git clone https://github.com/just-unknown-dev/just-game-engine-cli.git just_game_engine_cli
cd just_game_engine_cli
dart pub get
dart test
```

If you're working from the Just engine monorepo, run every command from `packages/just_game_engine_cli`.

**Running the commands from source.** `bin/just_plugin.dart` is the entry point `just` runs (`dart run just_game_engine_cli:just_plugin <arguments>`). Run it directly with a game project named by `--project`:

```bash
dart run bin/just_plugin.dart game --help
dart run bin/just_plugin.dart game check --project ../my_game
```

To have `just` use your checkout in a game, link the game to it: `just dev link <folder with your just_* checkouts>` in the game (the folder must be named `just_game_engine_cli`).

---

## Working Against Unpublished Dependencies

Besides `args`, the package depends on `just_core_cli` (the command framework and the project toolkit) and `just_game_engine_formats` (the saved formats). When a change needs an unreleased version of one, check it out next to this repository and point this package at it with a `pubspec_overrides.yaml` in the repository root:

```yaml
# pubspec_overrides.yaml: local only, never commit it.
dependency_overrides:
  just_core_cli:
    path: ../just_core_cli
  just_deflate:
    path: ../just_deflate
  just_game_engine_formats:
    path: ../just_game_engine_formats
```

Then run `dart pub get`. Delete the file and run `dart pub get` again to go back to the published versions. `.gitignore` already ignores the file.

Do not change `pubspec.yaml` to a path dependency. If your pull request needs a version of a dependency that is not published yet, say so in the pull request: this package can only be released after it.

Two kinds of code depend on this package. Every game project has it in its `dev_dependencies` (its version comes from just_core_cli's `ToolSet`; the engine's packages' versions come from this package's `GameSet`), and the game templates' `tool/check_release_*.dart` scripts use the release toolkit. If you change the public API, `just_plugin.json` or what `game init` writes, say in the pull request what they will need.

---

## How the Package Fits Together

| Folder | Contents |
|--------|----------|
| `bin/` | `just_plugin.dart`: the entry point `just` runs, `runJustPlugin(arguments, [GameCommand()])` |
| `just_plugin.json` | The command `game`, and the hooks `create`, `check`, `doctor`, `upgrade`, `migrate` and `link` |
| `lib/src/commands/` | `GameCommand` and its subcommands: `run`, `build`, `check`, `scene`, `doctor`, `upgrade`, `migrate`, and the hidden `init` and `link`; `MigrationSafety` |
| `lib/src/create/` | `GameSet` (the engine's packages and SDK floors); `GameTemplate` (the template filled in, the runner and entitlement patches); `templates.g.dart`, generated from `templates/` |
| `lib/src/project/` | `GameEntries` and `EditorPresence`; `GameProject`, the extension on `JustProject` that reads a game on disk for the checks |
| `lib/src/release/` | `ReleaseRules`, `ReleaseImports`, `ReleaseBuild` and `FormatsCheck`: what `build`, `check` and `migrate` prove and rewrite, worked out from text |
| `lib/just_game_engine_cli.dart` | The public library: the toolkit everywhere, and `src/native.dart` (the commands, `MigrationSafety`, `GameProject`) where `dart:io` is — `src/web.dart` on the web |
| `templates/`, `tool/` | The bundled game template's source, and the bundler (see [below](#templates-and-the-tool-folder)) |
| `example/` | The release-import check from a script |
| `test/` | The tests; `test/support/fake_launcher.dart` and `test/fixtures/runners/` |

A few rules hold the package together. Keep them:

- **The toolkit runs on the web.** `lib/src/create/`, `lib/src/release/`, `game_entries.dart` and `editor_presence.dart` import `package:just_core_cli/just_core_cli.dart`, never `dart:io` or `package:just_core_cli/project.dart`: they work on text, and pub.dev lists the package for the web and WebAssembly because they do. Reading the disk goes in `GameProject` (`lib/src/project/game_project.dart`), running things in the commands; both reach the library only through `src/native.dart`. `test/web_test.dart` tests the toolkit in a browser.
- **Saved files are migrated by `just_game_engine_formats`, never here.** `game migrate`, `game scene migrate` and `game check` call `SceneFormat`, `TimelineFormat` and `AnimatorGraph`, the code the engine runs as it loads a file. Files are written as the editor writes them: JSON indented by two spaces, `SceneStarters.encode`, `SceneManifest.encode`, `AnimatorGraph.encode`. Only the kinds in `FormatsCheck.migratable` are ever rewritten.
- **A change to a project is all or nothing.** A command that writes project files takes just_core_cli's `ProjectLock`, calls `ProjectTransaction.recover`, writes through a `ProjectTransaction`, and commits or rolls back — passing `trashRoot: GameTemplate.editorTrash` to both, so what it replaces lands in the editor's trash (just_core_cli's default is its own `.just_trash`).
- **Not under an open editor, not without the kits' rules.** The editor holds the scenes in memory and would save over a change, so the commands that write scenes refuse while `JustProject.editorIsOpen()` (`GameProject`: the heartbeat file `.dart_tool/just_core_cli/editor.lock`, which the editor writes) unless given `--force`. `MigrationSafety` refuses to rewrite old files while an installed kit has no `migrate` hook in its `just_plugin.json`, unless given `--engine-only`.
- **`game migrate --check` answers before `just upgrade` changes anything, and again with the new packages before it commits.** It must change nothing, and fail with the reason whenever the real run would be refused — and while the editor is open whatever the files, since the packages an upgrade fetches can bring newer formats. The real run refuses an open editor only when it has files to rewrite, exits 0 when every file is current, and says what it rewrote in its `--json` result's `migrated`. `just upgrade -- --engine-only` (or `-- --force`) passes the flag to the checks and the run alike.
- **`game init` keeps the tools.** `just create` adds just_core_cli and this package as one-line dev dependencies; the template's pubspec must list them the same way (from `GameTemplate.directPackages`), or `just upgrade` can't move them. A test checks it.
- **The engine's versions are this package's.** `GameSet.current` is what `game init` writes, `game doctor` checks and `game upgrade` moves to; just_core_cli's `ToolSet` holds only the tools. `game upgrade` writes one-line bumps to `pubspec.yaml` alone — never `pub get`, never the project lock: `just upgrade` runs it inside its transaction and fetches.
- **The Asset Store's place in a game is here.** `game link` registers store items after `just dev link` and refuses `just dev unlink` while only the links supply a package (`GameSet.linkOnly`); `game doctor` checks `just_store.lock.json`'s links. The store is called through `runTrustedPlugin`.
- **Hooks are commands.** Every hook in `just_plugin.json` names a subcommand of `game`; a test checks it. `just` passes the hooks `--json` and `--verbose` when it was given them, and `game init` gets `--title`, `--org`, `--platforms`, `--template`, `--source` and `--local` from `just create` (`--yes` only when the user gave it; the engine's set is `GameSet.current`, the tools' set the one `just.json` names).
- **The release checks name real things.** `ReleaseRules.coreForbidden`, `coreClassNames`, `coreStrings`, `physics3DClassNames` and `physics3DStrings` are names from the editor, the tools, the engine and the physics engine that must not appear in a release build (a 2-D one, for the 3-D names). When one is renamed there, rename it here, or the check proves nothing.

---

## Templates and the `tool/` Folder

`just game init` writes a game from a bundled template; `templates/empty/` is the only one. `tool/bundle_templates.dart` compiles the templates into `lib/src/create/templates.g.dart`, each file as text with CRLF turned into LF:

```bash
# After any change under templates/.
dart run tool/bundle_templates.dart
```

Never edit `templates.g.dart` by hand, and commit it with the template change. The test `the bundled templates are the files in templates/` in `test/templates_test.dart` fails when it is out of date, and CI regenerates it and fails on any difference.

- `GameTemplate.render` fills the placeholders through just_core_cli's `TemplateRenderer`, in one pass: `{{name}}`, `{{title}}` and its escaped forms (`{{title.dart}}`, `{{title.yaml}}`, `{{title.json}}`, `{{title.xml}}`, `{{title.c}}`), `{{App}}`, plus `{{dart}}`, `{{set}}`, `{{org}}`, `{{dependencies}}` and `{{dev_dependencies}}`. They make the files invalid Dart, so a template's Dart files are named `.dart.tmpl`; the bundler drops the suffix. That keeps them away from the analyzer, `dart format` and pub.dev's score.
- Don't add a scene, `scenes.json` or `just.json` to a template: `render` adds `assets/scenes/level_01.scene.json` from `SceneStarters.twoD` and the scene list from `SceneManifest`, and `just create` writes `just.json`.
- The template's `lib/main.dart` must never import the editor, and `lib/main_editor.dart` keeps the editor behind `kDebugMode`: `game build`, `game check` and `game doctor` rely on that.
- Try a template change for real: `just create <an empty folder>/my_game --local <folder with your just_* checkouts>` (with this checkout among them), then `flutter analyze` and `flutter test` in `my_game`.

---

## Running the Tests

Run every command from the repository root: the tests read `just_plugin.json`, `templates/` and `test/fixtures/` by relative path.

```bash
dart test
dart test test/migrate_test.dart
# The toolkit in a browser, as JavaScript and as WebAssembly (the test
# files that need dart:io are @TestOn('vm') and skipped).
dart test -p chrome
dart test -p chrome -c dart2wasm
```

CI (`.github/workflows/ci.yml`) runs `dart analyze --fatal-infos`, a `dart format` check and `dart test` on Linux, Windows and macOS, checks that `templates.g.dart` is current, runs `dart pub publish --dry-run`, and runs the browser tests in Chrome as JavaScript and WebAssembly.

**No test starts Flutter, pub or a plugin.** The command tests run `runJustPlugin(args, [GameCommand()], context: ...)` on a temporary folder, with the output in `StringBuffer`s and a `FakeLauncher` (`test/support/fake_launcher.dart`) that records what would have run and plays `pub get`. `test/fixtures/runners/` holds the runner files `flutter create` 3.47.6 makes, some CRLF on purpose.

---

## Coding Guidelines

- **Formatting.** Run `dart format lib bin test tool example`; CI fails on unformatted code. The bundler writes `templates.g.dart` already formatted.
- **Analysis.** `dart analyze --fatal-infos` must report no issues at all.
- **Pure Dart.** Nothing in `lib/`, `bin/` or `tool/` may import Flutter.
- **No direct I/O in commands.** Use `context`, `output` and `context.launcher`, never `print`, `stdout` or `Process`. Call other plugins (the Asset Store) with just_core_cli's `runTrustedPlugin`: it runs them under the trust rule every plugin command follows.
- **Documentation.** Give every public API a `///` doc comment. Describe user-visible changes in [CHANGELOG.md](CHANGELOG.md), and update [README.md](README.md) if a command or the public API changes.
- **Tests.** Add or update tests for any behaviour you change. A bug fix comes with a test that fails without it.

---

## Submitting a Pull Request

1. Create a topic branch from `main`.
2. Make your change, following the [Coding Guidelines](#coding-guidelines).
3. Check that everything passes:
   ```bash
   dart format lib bin test tool example
   dart analyze --fatal-infos
   dart test
   ```
   If you changed `templates/`, run `dart run tool/bundle_templates.dart` and try `just create --local` as described [above](#templates-and-the-tool-folder).
4. Commit with a [conventional commit message](#commit-message-convention).
5. Push to your fork and open a pull request against `main`. Say what changed and why, and list any unpublished `just_core_cli` or `just_game_engine_formats` version it needs.

---

## Releasing

1. Set the version in `pubspec.yaml`, and give `CHANGELOG.md` a `## <version>` section.
2. Publish what this version needs first, in this order: `just_game_engine_formats`, then `just_core_cli` (whose `ToolSet` names this package's version), then this package — and every version `GameSet.current` names must be on pub.dev (or, for the Asset Store, tagged in its repository) before people get it.
3. From a clean checkout of `main`, with no `pubspec_overrides.yaml`: `dart pub publish --dry-run`, then `dart pub publish`.
4. Tag `v<version>`. There are no binaries: `just` runs this package with `dart run`.

---

## Commit Message Convention

We use [Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>): <short summary>`, with the types `feat`, `fix`, `docs`, `refactor`, `perf`, `test` and `chore`. Use the command or the area as the scope: `run`, `build`, `check`, `scene`, `doctor`, `migrate`, `init`, `release`, `templates`, `tool` or `ci`. Mark a change that breaks the public API, a command's `--json` output or exit codes, or `just_plugin.json` with `!` and a `BREAKING CHANGE:` footer.

---

## License

By contributing to just_game_engine_cli you agree that your contributions will be licensed under the [BSD-3-Clause License](LICENSE).
