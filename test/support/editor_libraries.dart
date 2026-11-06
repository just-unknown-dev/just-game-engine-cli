// The editor's own public libraries, as a game would import them.

/// Every public library of the editor, its core and the Asset Store: each
/// one is editor code a release must never import.
///
/// `test/release/release_names_test.dart` checks that each is still a
/// library of its package (where the monorepo has the package beside this
/// one), so a test naming them guards something real.
const List<String> editorLibraries = [
  'package:just_game_engine_editor/just_game_engine_editor.dart',
  'package:just_game_engine_editor/asset_store.dart',
  'package:just_game_engine_editor/graphics.dart',
  'package:just_game_engine_editor/materials.dart',
  'package:just_editor_core/just_editor_core.dart',
  'package:just_editor_core/host.dart',
  'package:just_editor_core/io.dart',
  'package:just_editor_core/kit.dart',
  'package:just_asset_store/just_asset_store.dart',
];
