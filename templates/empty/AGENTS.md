# {{title}}: notes for AI assistants

A game made with the [Just Game Engine](https://engine.justunknown.com/), a
Flutter game engine. Its 2.x API is new and differs from 1.x and from other
Flutter engines such as Flame, so look it up instead of guessing it.

## Look it up

`.mcp.json` (Claude Code) and `.vscode/mcp.json` (VS Code) start
`just game mcp`: an MCP server with the engine's guides and API at the
versions this game resolved.

| Tool | What it gives |
|---|---|
| `search_docs` | Guide sections, package notes and API that match some words |
| `get_api` | A class or member's exact signature, docs and the import to use |
| `read_doc` | A whole guide (`ecs`, `scenes`, `physics-2d`, `input`, …) or one section |
| `project_info` | The engine packages and versions, the scenes, whether the editor is open |
| `list_scenes`, `validate_scenes` | The levels, and whether they load |
| `check_game` | The setup, and that a release holds no editor code |

Without it: the guides are at https://engine.justunknown.com/docs, the API at
https://pub.dev/documentation/just_game_engine/latest/, and the engine's
source is in the pub cache.

## Commands

```text
just game run --editor        # the game with the level editor (desktop, debug)
just game run                 # the game
flutter analyze               # static analysis
flutter test                  # the tests, the scenes test included
just game scene validate      # the scene files load
just check                    # no editor code in a release; saved files current
just doctor                   # the project's setup
```

## Layout

| Path | What |
|---|---|
| `lib/main.dart` | The game, as it ships. Never imports the editor. |
| `lib/main_editor.dart` | The game with the editor over it, inside `if (kDebugMode)`. |
| `lib/game/` | The game: its boot, components, systems and spawners. |
| `lib/editor/` | What the editor needs from the game. Never ships. |
| `assets/scenes/` | The levels: `<name>.scene.json`, in play order in `scenes.json`. |

## Rules that trip people up

- `Engine()` makes a new engine each call: make one and keep the reference
  (there is no `Engine.instance`). Find a subsystem with
  `engine.subsystem<T>()`; `getSystem` is deprecated.
- Data goes in components (classes extending `Component`), logic in systems
  (`System` subclasses) that query them. One component of each type per
  entity; every shape and sprite is a `RenderableComponent`, so a second
  drawing goes on a child entity.
- The world updates in fixed steps of 1/60 s: move things in
  `update(deltaTime)`, never by the wall clock. Systems run by priority,
  highest first (`SystemPriorities`), not in the order added.
- +Y is down: gravity is +Y, a jump is -Y, a positive angle turns clockwise.
- `TransformComponent` is in world space; a child's offset from its parent
  lives in its `ParentComponent`.
- The level editor writes the scene files. While it has the game open, it
  saves over changes made to them on disk: close it before editing a scene
  file by hand.
- Editor code stays in `lib/main_editor.dart` and `lib/editor/`; nothing
  `lib/main.dart` imports may reach it.

## Before you finish

Run `flutter analyze` and `flutter test`; after changing a scene, run
`just game scene validate`; after changing an entry point or the pubspec, run
`just check`.
