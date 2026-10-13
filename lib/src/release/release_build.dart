/// Proving from a release build itself that it holds no editor.
library;

import 'dart:convert';

import 'release_rules.dart';

/// What a check of a build found.
final class ReleaseReport {
  /// An empty report, for a check to fill in.
  ReleaseReport();

  /// What breaks the promise that the editor never ships.
  final List<String> errors = [];

  /// What is worth knowing but not a failure.
  final List<String> warnings = [];

  /// What was checked.
  final List<String> notes = [];

  /// Whether the build holds no editor.
  bool get ok => errors.isEmpty;
}

/// A release build's files, as read: what [ReleaseBuild.check] judges.
/// `JustProject.checkReleaseBuild` (the `GameProject` extension, where
/// `dart:io` is) reads them from a project's `build/` folder.
final class ReleaseBuildFiles {
  /// The [platform]'s build: its compiled Dart [code], the [natives] beside
  /// it, and the plugin lists.
  const ReleaseBuildFiles(
    this.platform, {
    required this.code,
    this.natives,
    this.nativesPath,
    this.pluginList,
    this.pluginListPath,
    this.pluginsDependencies,
  });

  /// One of [ReleaseBuild.platforms].
  final String platform;

  /// The compiled Dart, each file's bytes read as Latin-1, by the path the
  /// messages name it by: the AOT snapshot (`app.so`, `libapp.so`, `App`),
  /// or on the web `main.dart.js` and, from a `--wasm` build,
  /// `main.dart.wasm`.
  final Map<String, String> code;

  /// The names of the files in the folder of the app's native libraries,
  /// or null where there is none (the web).
  final List<String>? natives;

  /// The folder [natives] are in, for the messages.
  final String? nativesPath;

  /// The plugin list a CMake build generated (`generated_plugins.cmake`,
  /// Windows and Linux), or null.
  final String? pluginList;

  /// Where [pluginList] is, for the messages.
  final String? pluginListPath;

  /// The project's `.flutter-plugins-dependencies`, or null.
  final String? pluginsDependencies;
}

/// Checks a release build: the ground truth the import walk
/// (`ReleaseImports`) stands in for.
///
/// - The compiled Dart for names only the editor has. Class names survive
///   an AOT build unless it was obfuscated, which this refuses to judge; on
///   the web (JavaScript, and WebAssembly from a `--wasm` build) only
///   string literals survive.
/// - The native plugins the build linked, for those only dev dependencies
///   (the editor) bring. macOS links every plugin whatever the build
///   (flutter/flutter#163874): a warning there.
/// - In a 2-D game (one whose pubspec does not build Jolt), that neither
///   3-D physics' code nor Jolt's library is in it.
///
/// Run it right after `flutter build <platform> --release` (`just game
/// build` does), before a debug build or `pub get` rewrites the plugin lists.
abstract final class ReleaseBuild {
  /// The platforms a build can be checked for.
  static const List<String> platforms = ['windows', 'linux', 'macos', 'web'];

  /// A framework class every Flutter app's AOT snapshot names — unless the
  /// build was obfuscated.
  static const String frameworkClassName = 'MaterialApp';

  /// Checks [build] against [rules].
  static ReleaseReport check(ReleaseBuildFiles build, ReleaseRules rules) {
    final report = ReleaseReport();
    final web = build.platform == 'web';
    if (build.code.isEmpty) {
      report.errors.add('No compiled Dart in the ${build.platform} build.');
      return report;
    }
    final marker = rules.gameMarker;
    for (final MapEntry(key: path, value: code) in build.code.entries) {
      if (marker != null && !holds(code, marker)) {
        report.errors.add(
          '$path does not hold "$marker": not this '
          "game's build, or not one this check can read. (The marker is the "
          "game's title, from just.json.)",
        );
        return report;
      }
      if (!web && !code.contains(frameworkClassName)) {
        report.errors.add(
          '$path looks obfuscated (no "$frameworkClassName"): names would '
          'prove nothing. Check a build made without --obfuscate.',
        );
        return report;
      }
    }
    final physics = <String, List<String>>{};
    for (final MapEntry(key: path, value: code) in build.code.entries) {
      final found = markersIn(code, rules, classNames: !web);
      if (found.isEmpty) {
        report.notes.add('No editor code in $path.');
      } else {
        report.errors.add('Editor code in $path: ${found.join(', ')}.');
      }
      physics[path] = physics3DMarkersIn(code, classNames: !web);
    }
    _check3D(build, rules, physics, report);
    _checkPlugins(build, report);
    return report;
  }

  /// Whether compiled [code] (a build's bytes read as Latin-1) holds the
  /// string literal [text], however the compiler wrote it: as Latin-1 (an
  /// AOT snapshot's one-byte strings, ASCII anywhere), UTF-16LE (an AOT
  /// snapshot's other strings), UTF-8 (WebAssembly), or with JavaScript
  /// escapes (`\xe9`, `ゲ`, `\"`, as dart2js writes anything beyond
  /// ASCII).
  static bool holds(String code, String text) =>
      _forms(text).any(code.contains);

  static Iterable<String> _forms(String text) sync* {
    yield text;
    final units = text.codeUnits;
    if (units.any((u) => u > 0x7F)) {
      yield latin1.decode(utf8.encode(text));
      yield String.fromCharCodes([
        for (final u in units) ...[u & 0xFF, u >> 8],
      ]);
    }
    // In a JS string quoted with nothing escaped, with " or with '.
    for (final upper in [false, true]) {
      for (final quote in const <int?>[null, 0x22, 0x27]) {
        final b = StringBuffer();
        for (final u in units) {
          String hex(int width) {
            final h = u.toRadixString(16).padLeft(width, '0');
            return upper ? h.toUpperCase() : h;
          }

          if (quote != null && (u == quote || u == 0x5C)) {
            b.write('\\${String.fromCharCode(u)}');
          } else if (u < 0x80) {
            b.writeCharCode(u);
          } else if (u < 0x100) {
            b.write('\\x${hex(2)}');
          } else {
            b.write('\\u${hex(4)}');
          }
        }
        final escaped = '$b';
        if (escaped != text) yield escaped;
      }
    }
  }

  /// The editor's names [rules] knows that are in compiled Dart [code] — a
  /// build's bytes read as Latin-1. With [classNames] false (the web) only
  /// string literals count.
  static List<String> markersIn(
    String code,
    ReleaseRules rules, {
    required bool classNames,
  }) => [
    for (final s in rules.strings)
      if (code.contains(s)) s,
    if (classNames)
      for (final c in rules.classNames)
        if (code.contains(c)) c,
  ];

  /// 3-D physics' names that are in compiled Dart [code]. With [classNames]
  /// false (the web) only string literals count.
  static List<String> physics3DMarkersIn(
    String code, {
    required bool classNames,
  }) => [
    for (final s in ReleaseRules.physics3DStrings)
      if (code.contains(s)) s,
    if (classNames)
      for (final c in ReleaseRules.physics3DClassNames)
        if (code.contains(c)) c,
  ];

  /// A 2-D game (its pubspec does not build Jolt) must hold no 3-D physics:
  /// neither its code, which only a `Physics3D` reaches, nor Jolt's native
  /// library. A 3-D game gets a note of what it holds.
  static void _check3D(
    ReleaseBuildFiles build,
    ReleaseRules rules,
    Map<String, List<String>> physics,
    ReleaseReport report,
  ) {
    final jolt = [
      for (final name in build.natives ?? const <String>[])
        if (name.startsWith(ReleaseRules.joltLibrary) ||
            name.startsWith('lib${ReleaseRules.joltLibrary}'))
          name,
    ];
    final inCode = physics.values.any((m) => m.isNotEmpty);
    if (rules.buildsJolt) {
      report.notes.add(
        '3D physics: ${inCode ? 'in the code' : 'no code found'}'
        '${build.natives == null
            ? ''
            : jolt.isEmpty
            ? ', no Jolt library'
            : ', ${jolt.join(', ')}'}.',
      );
      return;
    }
    physics.forEach((path, markers) {
      if (markers.isEmpty) return;
      report.errors.add(
        '3D physics code in $path (${markers.join(', ')}), but this game '
        'does not build Jolt: something reaches 3D physics without a '
        'Physics3D, and a 2D game should carry none of it.',
      );
    });
    if (jolt.isNotEmpty) {
      report.errors.add(
        '${jolt.join(', ')} is in ${build.nativesPath}, but this '
        "game's pubspec does not ask for Jolt (hooks: user_defines: just_jolt: "
        'build: true): delete the folder and build again, or turn the '
        'switch on if the game is 3D.',
      );
    }
    if (!inCode && jolt.isEmpty) {
      report.notes.add('No 3D physics in the build (a 2D game).');
    }
  }

  /// The native plugins only dev dependencies bring must be left out of
  /// the build (macOS: a warning).
  static void _checkPlugins(ReleaseBuildFiles build, ReleaseReport report) {
    final natives = build.natives;
    final devOnly = devOnlyPluginsIn(
      build.pluginsDependencies ?? '',
      build.platform,
    );
    if (devOnly.isEmpty || natives == null) return;
    final cmake = build.pluginList;
    final linked = cmake == null ? null : linkedPlugins(cmake);
    final leftOut = <String>[];
    for (final plugin in devOnly) {
      final left = natives.where(
        (f) => f.startsWith(plugin) || f.startsWith('lib$plugin'),
      );
      if (build.platform == 'macos') {
        if (left.isNotEmpty) {
          report.warnings.add(
            '$plugin is in the macOS app: Flutter links every plugin on '
            'macOS, dev dependencies too (flutter/flutter#163874).',
          );
        } else {
          leftOut.add(plugin);
        }
      } else if (linked != null && linked.contains(plugin)) {
        report.errors.add(
          '$plugin, which only a dev dependency brings, is in the plugin list '
          '${build.pluginListPath}: was this a release build?',
        );
      } else {
        leftOut.add(plugin);
        if (left.isNotEmpty) {
          report.warnings.add(
            '${left.join(', ')} is in ${build.nativesPath} but this '
            'build did not link $plugin: left from an older build. Delete the '
            'folder and build again for a clean one.',
          );
        }
      }
    }
    if (leftOut.isNotEmpty) {
      report.notes.add(
        'Dev-only plugins left out of the native build: '
        '${leftOut.join(', ')}.',
      );
    }
  }

  /// The native plugins for [platform] that only dev dependencies bring,
  /// from the text of a project's `.flutter-plugins-dependencies`; empty
  /// when it is not that file.
  static Set<String> devOnlyPluginsIn(String text, String platform) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return {};
    }
    final plugins = json is Map ? json['plugins'] : null;
    final list = plugins is Map ? plugins[platform] : null;
    if (list is! List) return {};
    return {
      for (final p in list)
        if (p is Map && p['dev_dependency'] == true && p['name'] is String)
          p['name'] as String,
    };
  }

  /// The plugins a CMake build links, from its generated plugin list.
  static Set<String> linkedPlugins(String cmake) {
    final out = <String>{};
    final list = RegExp(r'list\(APPEND FLUTTER_(?:FFI_)?PLUGIN_LIST([^)]*)\)');
    for (final m in list.allMatches(cmake)) {
      out.addAll(m.group(1)!.split(RegExp(r'\s+')).where((s) => s.isNotEmpty));
    }
    return out;
  }

  /// The WebAssembly file a web build loads, from its
  /// `flutter_bootstrap.js` (`main.dart.wasm`, relative to `build/web`), or
  /// null when it loads none: a build made without `--wasm`.
  static String? wasmIn(String bootstrap) => RegExp(
    r'''["']?mainWasmPath["']?\s*:\s*["']([^"']+)["']''',
  ).firstMatch(bootstrap)?.group(1);
}
