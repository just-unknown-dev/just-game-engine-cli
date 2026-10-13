/// What must never reach a release build, worked out from the project.
library;

import 'dart:convert';

import 'package:just_core_cli/just_core_cli.dart';

/// What a project's release build must not hold, and how to recognise the
/// game in one.
///
/// Nothing here is a list kept by hand in the project: the editor's own
/// packages are known, and every installed Asset Store item says in its
/// manifest (`just_store.json`) which of its libraries are editor-only and
/// which editor modules it has — so installing a kit guards it too.
/// `JustProject.releaseRules()` (the `GameProject` extension, where
/// `dart:io` is) reads them from a project on disk; [ReleaseRules.forGame]
/// makes them from the files' text, anywhere.
final class ReleaseRules {
  /// Rules banning [forbidden] imports and the project's `lib/editor/`,
  /// finding [classNames] and [strings] in compiled code, and knowing the
  /// game by [gameMarker].
  const ReleaseRules({
    required this.forbidden,
    required this.classNames,
    required this.strings,
    required this.gameMarker,
    this.buildsJolt = false,
  });

  /// Package names, or `package/path` prefixes, nothing in a release may
  /// import: `just_game_engine_editor`, `just_platformer_kit/editor.dart`.
  final List<String> forbidden;

  /// Class names only the editor and its modules have. They survive an AOT
  /// build unless it was obfuscated.
  final List<String> classNames;

  /// String literals only the editor has: these survive a minified web
  /// build too.
  final List<String> strings;

  /// A text every build of this game holds (its title), or null when it is
  /// not known: a build without it is not this game's.
  final String? gameMarker;

  /// Whether the project asks for Jolt Physics to be built (its pubspec's
  /// `hooks: user_defines: just_jolt: build: true`): a 3-D game. A game that
  /// does not is 2-D only, and its release must hold no 3-D physics at all.
  final bool buildsJolt;

  /// Class names only 3-D physics has: the engine's system and the Jolt
  /// engine. In a 2-D game's build they mean something reaches 3-D physics
  /// without a `Physics3D`.
  static const List<String> physics3DClassNames = [
    'PhysicsSystem3D',
    'JoltPhysicsEngine',
    'JoltWorld',
  ];

  /// String literals only 3-D physics has (they survive a minified web
  /// build): the 3-D rigid body's saved type id, and `Physics3D`'s own
  /// message.
  static const List<String> physics3DStrings = [
    'rigid_body_3d_d3ff8994',
    'Physics3D has not started',
  ];

  /// The start of Jolt's native library's file name, on every platform
  /// (`just_jolt.dll`, `libjust_jolt.so`, `just_jolt.framework`).
  static const String joltLibrary = 'just_jolt';

  /// The project's own folder of editor code, imported by relative path.
  static const String appEditorFolder = 'lib/editor/';

  /// What is editor-only whatever the project: the editor, the store, the
  /// tools (`just` and these commands), and the test helpers (the input
  /// system's, and the physics engine's fake 3-D engine).
  static const List<String> coreForbidden = [
    'just_game_engine_editor',
    'just_asset_store/',
    'just_asset_store_editor/',
    'just_core_cli/',
    'just_game_engine_cli/',
    'just_inputs/testing.dart',
    'just_physics_engine/testing.dart',
  ];

  /// The editor's own class names.
  static const List<String> coreClassNames = [
    'JustGameEditorPlugin',
    'EditorScope',
    'LevelDesignerSession',
    'AssetStoreModule',
    'StoreController',
  ];

  /// The editor's own string literals.
  static const List<String> coreStrings = [
    'Runtime editor initialized.',
    'Just Runtime Editor',
    'sprite_studio.open',
    'input_editor.open',
    'just.asset_store',
  ];

  /// The rules for a game: the core ones, plus what its installed store
  /// items declare — [storeItems], each item's id → its `just_store.json`.
  /// The game is known by [file]'s title, else by the `title:` of the
  /// MaterialApp in [gameSource] (its entry point's text,
  /// [gameMarkerIn]); [pubspec] says whether it builds Jolt
  /// ([buildsJoltIn]).
  factory ReleaseRules.forGame({
    JustProjectFile file = const JustProjectFile(),
    String pubspec = '',
    String? gameSource,
    Map<String, Map<String, Object?>> storeItems = const {},
  }) {
    final forbidden = [...coreForbidden];
    final classes = [...coreClassNames];
    for (final MapEntry(key: id, value: manifest) in storeItems.entries) {
      final editor = manifest['editor'];
      if (editor is! Map) continue;
      final libraries = editor['editorOnlyLibraries'];
      if (libraries is List) {
        for (final lib in libraries) {
          if (lib is! String) continue;
          final entry = lib == '*' ? '$id/' : '$id/$lib';
          // `kit` and `kit/` both forbid the whole package: one is enough.
          if (!forbidden.contains(entry) && !forbidden.contains(id)) {
            forbidden.add(entry);
          }
        }
      }
      final modules = editor['modules'];
      if (modules is List) {
        for (final m in modules) {
          final c = m is Map ? m['class'] : null;
          if (c is String && !classes.contains(c)) classes.add(c);
        }
      }
    }
    return ReleaseRules(
      forbidden: forbidden,
      classNames: classes,
      strings: coreStrings,
      gameMarker: gameMarkerIn(file, gameSource),
      buildsJolt: buildsJoltIn(pubspec),
    );
  }

  /// Whether [uri], a `package:` URI an import names, is one nothing in a
  /// release may import ([forbidden]). A bare package name forbids the
  /// whole package, and only that one: `just_game_engine_editor` is not
  /// `just_game_engine_editor_tools`.
  bool forbids(String uri) => forbidden.any(
    (f) => uri.startsWith(f.contains('/') ? 'package:$f' : 'package:$f/'),
  );

  /// Whether [pubspec] sets `hooks: user_defines: just_jolt: build: true`.
  static bool buildsJoltIn(String pubspec) {
    const want = ['hooks', 'user_defines', 'just_jolt', 'build'];
    final key = RegExp(r'^(\s*)([A-Za-z_][\w-]*)\s*:\s*([^#]*?)\s*(#.*)?$');
    final path = <(int, String)>[];
    for (final line in const LineSplitter().convert(pubspec)) {
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
      final m = key.firstMatch(line);
      if (m == null) continue;
      final indent = m.group(1)!.length;
      while (path.isNotEmpty && path.last.$1 >= indent) {
        path.removeLast();
      }
      path.add((indent, m.group(2)!));
      if (path.length == want.length &&
          [for (final p in path) p.$2].join('/') == want.join('/')) {
        return m.group(3) == 'true';
      }
    }
    return false;
  }

  /// The game's title: [file]'s (`just.json`), else the `title:` of the
  /// MaterialApp in [gameSource], the text of the game's entry point.
  static String? gameMarkerIn(JustProjectFile file, String? gameSource) {
    if (file.title != null) return file.title;
    if (gameSource == null) return null;
    return RegExp(
      r'''title:\s*(['"])([^'"]+)\1''',
    ).firstMatch(gameSource)?.group(2);
  }

  /// The installed store items `just_store.lock.json`'s text [lock] lists,
  /// by id: the path each was installed or linked at (relative to the
  /// project, or absolute), or null when pub put it where it puts packages.
  /// Empty when [lock] is not a lockfile.
  static Map<String, String?> storeItemsIn(String lock) {
    final Object? json;
    try {
      json = jsonDecode(lock);
    } on FormatException {
      return const {};
    }
    final items = json is Map ? json['items'] : null;
    if (items is! Map) return const {};
    return {
      for (final MapEntry(:key, :value) in items.entries)
        '$key': switch (value) {
          {'path': final String path} => path,
          _ => null,
        },
    };
  }
}
