/// A game on disk: what the game's checks read from a project.
library;

import 'dart:convert';
import 'dart:io';

import 'package:just_core_cli/project.dart';

import '../release/formats_check.dart';
import '../release/release_build.dart';
import '../release/release_imports.dart';
import '../release/release_rules.dart';
import 'editor_presence.dart';
import 'game_entries.dart';

/// What the game's checks read from a project on disk: its release rules,
/// the import walk from its entry point, its release builds, its saved
/// formats, and whether the editor has it open.
///
/// The checks themselves — [ReleaseRules], [ReleaseImports],
/// [ReleaseBuild], [FormatsCheck], [EditorPresence] — work on text and run
/// on every platform, the web included; these read their input from the
/// project's files.
extension GameProject on JustProject {
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
  /// the project's own `lib/editor/`.
  List<String> editorReachableFrom(String entry, {ReleaseRules? rules}) {
    final r = rules ?? releaseRules();
    final packages = PackageConfig.read(root)?.packages ?? const {};
    // Paths compared as the disk compares them: case aside on Windows and
    // macOS, where Foo.dart and foo.dart are one file.
    final fold = Platform.isWindows || Platform.isMacOS;
    String key(String at) => fold ? at.toLowerCase() : at;
    // With its slash: lib/editor_theme.dart is not in lib/editor/.
    final editorFolder = key('${path(ReleaseRules.appEditorFolder)}/');
    final seen = <String>{};
    final offenders = <String>[];

    void visit(File from, List<String> chain) {
      if (!seen.add(key(normalPath(from.absolute.path)))) return;
      final String source;
      try {
        source = from.readAsStringSync();
      } on FileSystemException {
        return;
      }
      for (final uri in ReleaseImports.dartUrisIn(source)) {
        final next = _resolve(uri, from, packages);
        if (next == null) continue;
        final trail = [...chain, uri];
        final nextPath = normalPath(
          next.absolute.uri.normalizePath().toFilePath(),
        );
        if (r.forbids(uri) || key(nextPath).startsWith(editorFolder)) {
          offenders.add(trail.join(' -> '));
          continue;
        }
        if (next.existsSync()) visit(next, trail);
      }
    }

    visit(file(entry), [entry]);
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

  /// Whether the editor has this project open, as of [now]: it touched its
  /// heartbeat ([EditorPresence.path]) less than [EditorPresence.stale]
  /// ago.
  bool editorIsOpen({DateTime? now}) {
    final heartbeat = file(EditorPresence.path);
    try {
      if (!heartbeat.existsSync()) return false;
      return EditorPresence.isFresh(heartbeat.lastModifiedSync(), now: now);
    } on FileSystemException {
      return false; // Removed as the editor closed.
    }
  }
}

String _latin1(File f) =>
    latin1.decode(f.readAsBytesSync(), allowInvalid: true);

File? _resolve(String uri, File from, Map<String, ResolvedPackage> packages) {
  if (uri.startsWith('package:')) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    final lib = packages[rest.substring(0, slash)];
    if (lib == null) return null;
    return File('${lib.libPath}/${rest.substring(slash + 1)}');
  }
  return File.fromUri(from.absolute.uri.resolve(uri));
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
