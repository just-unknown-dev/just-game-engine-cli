/// A game on disk: what the game's checks read from a project.
library;

import 'dart:convert';
import 'dart:io';

import 'package:just_core_cli/project.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart';

import '../game/game.dart';
import '../release/release.dart';

/// What the game's checks read from a project on disk: its release rules,
/// the import walk from its entry point, its release builds, its saved
/// formats, and whether the editor has it open.
///
/// The checks themselves — [ReleaseRules], [ReleaseImports],
/// [ReleaseBuild], [FormatsCheck], and the editor's [EditorHeartbeat] (from
/// just_game_engine_formats) — work on text and run on every platform,
/// the web included; these read their input from the project's files.
extension ProjectGame on JustProject {
  /// This game's release rules ([ReleaseRules.forGame]): from its
  /// `just.json`, its pubspec, its entry point ([GameEntries.game]) and
  /// what each installed store item declares ([storeManifests]).
  ReleaseRules releaseRules() {
    final file = readProjectFile();
    return ReleaseRules.forGame(
      file: file,
      pubspec: readText(JustProject.pubspec) ?? '',
      gameSource: readText(GameEntries.game(file)),
      storeItems: storeManifests(),
    );
  }

  /// Every installed store item's manifest (`just_store.json`), by id: the
  /// items `just_store.lock.json` lists ([ReleaseRules.storeItemsIn]), each
  /// found at its recorded path or, when it has none, where pub put it. An
  /// item without a readable manifest is left out.
  Map<String, Map<String, Object?>> storeManifests() {
    final lock = readText('just_store.lock.json');
    if (lock == null) return const {};
    final items = ReleaseRules.storeItemsIn(lock);
    if (items.isEmpty) return const {};
    final resolved = PackageConfig.read(root)?.packages ?? const {};
    final out = <String, Map<String, Object?>>{};
    items.forEach((id, at) {
      final folder = at == null
          ? resolved[id]?.rootPath
          : (File(at).isAbsolute ? at : path(at));
      if (folder == null) return;
      final manifest = File('$folder/just_store.json');
      try {
        if (!manifest.existsSync()) return;
        final json = jsonDecode(manifest.readAsStringSync());
        if (json is Map<String, Object?>) out[id] = json;
      } on FormatException {
        return;
      } on FileSystemException {
        return;
      }
    });
    return out;
  }

  /// Every way editor code is reachable from [entry] (relative to the
  /// project), as `entry -> uri -> uri` trails; empty when none is.
  ///
  /// It follows every `import`, `export` and `part`
  /// ([ReleaseImports.dartUrisIn]) through the project and the packages pub
  /// resolved, and stops at a library [rules] forbid
  /// ([ReleaseRules.forbids]; by default this game's [releaseRules]) or at
  /// the project's own `lib/editor/`. A forbidden import counts whether or
  /// not pub resolved its package.
  ///
  /// It looks into a package only when the package can reach editor code:
  /// when it, or something it depends on (`.dart_tool/package_graph.json`),
  /// is a package [rules] name or the project itself. A package that can't
  /// depend on the editor can't import it, so Flutter and the like are never
  /// read. Without a package graph every package is walked.
  ///
  /// Throws [ReleaseImportsUnchecked] when it could not look everywhere it
  /// had to — [entry] is not there, the project's packages were never
  /// fetched, an import names a package pub did not resolve or a file that
  /// is not there — rather than say nothing is reachable without having
  /// looked.
  List<String> editorReachableFrom(String entry, {ReleaseRules? rules}) {
    final r = rules ?? releaseRules();
    final start = file(entry);
    final startSource = _readOrNull(start);
    if (startSource == null) {
      throw ReleaseImportsUnchecked(entry, [
        "There is no $entry: is just.json's entry.game right?",
      ]);
    }
    final config = PackageConfig.read(root);
    if (config == null) {
      throw ReleaseImportsUnchecked(entry, [
        "The project's packages have not been fetched (there is no "
            '.dart_tool/package_config.json): run `flutter pub get` first.',
      ]);
    }
    final packages = config.packages;
    final safe = _cannotReachEditor(PackageGraph.read(root), r);
    // Paths compared as the disk compares them: case aside on Windows and
    // macOS, where Foo.dart and foo.dart are one file.
    final fold = Platform.isWindows || Platform.isMacOS;
    String key(String at) => fold ? at.toLowerCase() : at;
    String pathOf(File f) =>
        normalPath(f.absolute.uri.normalizePath().toFilePath());
    // With its slash: lib/editor_theme.dart is not in lib/editor/.
    final editorFolder = key('${path(ReleaseRules.appEditorFolder)}/');
    final seen = <String>{key(pathOf(start))};
    final offenders = <String>[];
    final unchecked = <String>[];

    void visit(File from, String source, List<String> chain) {
      for (final uri in ReleaseImports.dartUrisIn(source)) {
        final trail = [...chain, uri];
        // Asked first: a forbidden import is one whether or not its
        // package was resolved.
        if (r.forbids(uri)) {
          offenders.add(trail.join(' -> '));
          continue;
        }
        final File next;
        if (uri.startsWith('package:')) {
          final rest = uri.substring('package:'.length);
          final slash = rest.indexOf('/');
          final name = slash < 0 ? rest : rest.substring(0, slash);
          if (slash < 0) {
            unchecked.add('${trail.join(' -> ')} names no library.');
            continue;
          }
          if (safe.contains(name)) continue;
          final lib = packages[name];
          if (lib == null) {
            unchecked.add(
              '${trail.join(' -> ')} names package $name, which pub did not '
              'resolve.',
            );
            continue;
          }
          next = File('${lib.libPath}/${rest.substring(slash + 1)}');
        } else {
          next = File.fromUri(from.absolute.uri.resolve(uri));
        }
        final nextPath = key(pathOf(next));
        if (nextPath.startsWith(editorFolder)) {
          offenders.add(trail.join(' -> '));
          continue;
        }
        if (!seen.add(nextPath)) continue;
        final text = _readOrNull(next);
        if (text == null) {
          // What it would hold (a part not generated yet, say) is unknown.
          unchecked.add('${trail.join(' -> ')} is not there.');
          continue;
        }
        visit(next, text, trail);
      }
    }

    visit(start, startSource, [entry]);
    if (unchecked.isNotEmpty) {
      throw ReleaseImportsUnchecked(entry, unchecked, reachable: offenders);
    }
    return offenders;
  }

  /// The release build for [platform] (one of [ReleaseBuild.platforms]),
  /// read from `build/` and checked ([ReleaseBuild.check]) against [rules],
  /// by default this game's [releaseRules].
  ///
  /// On the web the JavaScript is checked, and the WebAssembly too when
  /// the build's `flutter_bootstrap.js` loads it (`--wasm`). A
  /// `main.dart.wasm` the build doesn't load is a warning: left from an
  /// older build.
  ReleaseReport checkReleaseBuild(String platform, {ReleaseRules? rules}) {
    final r = rules ?? releaseRules();
    final layout = _layout(root, platform);
    final codeFile = layout.code;
    if (!codeFile.existsSync()) {
      return ReleaseReport()
        ..errors.add(
          'No release build for $platform at ${normalPath(codeFile.path)}: '
          'build it first: `just game build $platform` (or `flutter build '
          '$platform --release`).',
        );
    }
    final code = {normalPath(codeFile.path): _latin1(codeFile)};
    final warnings = <String>[];
    if (platform == 'web') {
      final bootstrap = readText('build/web/flutter_bootstrap.js');
      final loaded = bootstrap == null
          ? 'main.dart.wasm'
          : ReleaseBuild.wasmIn(bootstrap);
      final wasm = File('$root/build/web/${loaded ?? 'main.dart.wasm'}');
      if (loaded != null && wasm.existsSync()) {
        code[normalPath(wasm.path)] = _latin1(wasm);
      } else if (loaded != null && bootstrap != null) {
        warnings.add(
          'flutter_bootstrap.js loads $loaded, which is not in build/web: '
          'only the JavaScript was checked.',
        );
      } else if (loaded == null && wasm.existsSync()) {
        warnings.add(
          '${normalPath(wasm.path)} is not part of this build (its '
          'flutter_bootstrap.js loads no WebAssembly): left from an older '
          '--wasm build. Delete build/web and build again for a clean one.',
        );
      }
    }
    final natives = layout.natives;
    final pluginList = layout.pluginList;
    final report = ReleaseBuild.check(
      ReleaseBuildFiles(
        platform,
        code: code,
        natives: natives == null
            ? null
            : natives.existsSync()
            ? [
                for (final e in natives.listSync())
                  e.uri.pathSegments.where((s) => s.isNotEmpty).last,
              ]
            : const [],
        nativesPath: natives == null ? null : normalPath(natives.path),
        pluginList: pluginList != null && pluginList.existsSync()
            ? pluginList.readAsStringSync()
            : null,
        pluginListPath: pluginList == null ? null : normalPath(pluginList.path),
        pluginsDependencies: readText('.flutter-plugins-dependencies'),
      ),
      r,
    );
    return report..warnings.addAll(warnings);
  }

  /// The native plugins for [platform] that only dev dependencies bring,
  /// from `.flutter-plugins-dependencies` ([ReleaseBuild.devOnlyPluginsIn]).
  Set<String> devOnlyPlugins(String platform) => ReleaseBuild.devOnlyPluginsIn(
    readText('.flutter-plugins-dependencies') ?? '',
    platform,
  );

  /// Every versioned file in the project's `assets/`, checked
  /// ([FormatsCheck.check]) and sorted by path. A file that can't be read
  /// is a finding too ([FormatsCheck.unreadable]).
  List<FormatFinding> checkFormats() {
    final assets = dir('assets');
    if (!assets.existsSync()) return const [];
    final files = assets.listSync(recursive: true).whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final out = <FormatFinding>[];
    for (final f in files) {
      final rel = relativeOf(f.absolute.path) ?? normalPath(f.path);
      if (FormatsCheck.kindOf(rel) == null) continue;
      final String text;
      try {
        text = f.readAsStringSync();
      } on FileSystemException catch (e) {
        out.add(FormatsCheck.unreadable(rel, e.osError?.message ?? e.message)!);
        continue;
      }
      out.add(FormatsCheck.check(rel, text)!);
    }
    return out;
  }

  /// Whether the editor has this project open, as of [now]: its heartbeat
  /// file ([EditorHeartbeat.path]) is there and not stale
  /// ([EditorHeartbeat.isStale]).
  bool editorIsOpen({DateTime? now}) {
    final heartbeat = file(EditorHeartbeat.path);
    try {
      if (!heartbeat.existsSync()) return false;
      final beat = EditorHeartbeat.decode(
        _latin1(heartbeat),
        modified: heartbeat.lastModifiedSync(),
      );
      return !beat.isStale(now ?? DateTime.now());
    } on FileSystemException {
      return false; // Removed as the editor closed.
    }
  }
}

String _latin1(File f) =>
    latin1.decode(f.readAsBytesSync(), allowInvalid: true);

/// [f]'s text, or null when it isn't there or can't be read.
String? _readOrNull(File f) {
  try {
    return f.readAsStringSync();
  } on FileSystemException {
    return null;
  }
}

/// The packages in [graph] that can't reach what [rules] forbid: neither
/// they nor anything they depend on, all the way down, is a package [rules]
/// name (whole or in part) or a root of [graph] (whose `lib/editor/` is
/// forbidden). Empty without a graph: then nothing is known to be safe.
Set<String> _cannotReachEditor(PackageGraph? graph, ReleaseRules rules) {
  if (graph == null) return const {};
  // Who depends on each package. (A root's dev dependencies need no edge:
  // a root is always walked.)
  final dependents = <String, Set<String>>{};
  for (final node in graph.nodes.values) {
    for (final d in node.dependencies) {
      (dependents[d] ??= {}).add(node.name);
    }
  }
  final reaches = <String>{};
  final queue = [
    for (final f in rules.forbidden) f.split('/').first,
    ...graph.roots,
  ];
  while (queue.isNotEmpty) {
    final name = queue.removeLast();
    if (reaches.add(name)) queue.addAll(dependents[name] ?? const {});
  }
  return {
    for (final name in graph.nodes.keys)
      if (!reaches.contains(name)) name,
  };
}

/// The architecture folder under [base] (`x64`, `arm64`) whose [code] file
/// was built last; `<base>/x64` when none has one.
String _newestArch(String base, String code) {
  final dir = Directory(base);
  if (!dir.existsSync()) return '$base/x64';
  String? newest;
  DateTime? when;
  for (final d in dir.listSync().whereType<Directory>()) {
    final f = File('${d.path}/$code');
    if (!f.existsSync()) continue;
    final modified = f.lastModifiedSync();
    if (when == null || modified.isAfter(when)) {
      when = modified;
      newest = normalPath(d.path);
    }
  }
  return newest ?? '$base/x64';
}

/// Where [platform]'s release build under the project at [r] keeps its
/// compiled Dart, its native libraries and its generated plugin list.
({File code, Directory? natives, File? pluginList}) _layout(
  String r,
  String platform,
) {
  switch (platform) {
    case 'windows':
      final arch = _newestArch(
        '$r/build/windows',
        'runner/Release/data/app.so',
      );
      final out = '$arch/runner/Release';
      return (
        code: File('$out/data/app.so'),
        natives: Directory(out),
        pluginList: File('$r/windows/flutter/generated_plugins.cmake'),
      );
    case 'linux':
      final arch = _newestArch(
        '$r/build/linux',
        'release/bundle/lib/libapp.so',
      );
      return (
        code: File('$arch/release/bundle/lib/libapp.so'),
        natives: Directory('$arch/release/bundle/lib'),
        pluginList: File('$r/linux/flutter/generated_plugins.cmake'),
      );
    case 'macos':
      final products = Directory('$r/build/macos/Build/Products/Release');
      final app = products.existsSync()
          ? products
                .listSync()
                .whereType<Directory>()
                .where((d) => d.path.endsWith('.app'))
                .firstOrNull
          : null;
      final frameworks =
          '${app?.path ?? '${products.path}/?.app'}/Contents/Frameworks';
      return (
        code: File('$frameworks/App.framework/App'),
        natives: Directory(frameworks),
        pluginList: null,
      );
    case 'web':
      return (
        code: File('$r/build/web/main.dart.js'),
        natives: null,
        pluginList: null,
      );
  }
  throw ArgumentError.value(
    platform,
    'platform',
    'one of ${ReleaseBuild.platforms}',
  );
}
