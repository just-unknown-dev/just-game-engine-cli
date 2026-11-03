# {{title}}

A game made with the [Just Game Engine](https://engine.justunknown.com/).

## Run it

```text
just game run --editor     # the game with the level editor (desktop)
just game run              # the game
just game build windows    # a release build, checked to hold no editor code
```

`ju` works anywhere `just` does, for machines where `just` is another tool.

## Add to it

```text
just store search             # what the Asset Store has
just add <id>                 # install an item: art, a kit, an editor tool
just game scene new cave      # a new level, listed in assets/scenes/scenes.json
just check                    # the release safety and the saved formats
just doctor                   # check the project's setup
just upgrade                  # newer tools and engine packages, old files migrated
```

## With an AI assistant

`AGENTS.md` tells an assistant how the game is built. `.mcp.json` (Claude
Code) and `.vscode/mcp.json` (VS Code) start `just game mcp`, which serves
it the engine's guides and API at the versions this game uses, and checks
its scenes and setup.

## Layout

| Path | What |
|---|---|
| `lib/main.dart` | The game, as it ships. Never imports the editor. |
| `lib/main_editor.dart` | The game with the editor over it (debug builds only). |
| `lib/game/` | The game: its boot, systems and spawners. |
| `lib/editor/` | What the editor needs from the game. Never ships. |
| `assets/scenes/` | The levels, as JSON the editor saves. |
| `just.json` | The project's title and the tool set it is on. |
