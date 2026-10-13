/// A new game's files: the bundled templates filled in, and the changes a
/// game makes to what `flutter create` wrote.
library;

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart';

import 'game_set.dart';
import 'templates.g.dart';

/// The files of a new game, and what it changes in the files
/// `flutter create` made.
abstract final class GameTemplate {
  /// The bundled templates' names.
  static Iterable<String> get names => bundledTemplates.keys;

  /// The template a new game starts from unless told otherwise.
  static const String empty = 'empty';

  /// The packages a new game depends on directly, in the order its pubspec
  /// lists them: the engine, then (dev) the tools and the editor. Their
  /// versions and sources come from the [GameSet] — the tools' from
  /// just_core_cli's [ToolSet].
  static const List<String> directPackages = [
    'just_game_engine',
    'just_core_cli',
    'just_game_engine_cli',
    'just_asset_store',
    'just_game_engine_editor',
    'just_asset_store_editor',
  ];

  /// [directPackages] as [game] (the engine's) or [tools] (the tools) has
  /// them. Throws [StateError] when neither has one.
  static List<SetPackage> direct(GameSet game, ToolSet tools) => [
    for (final name in directPackages)
      game[name] ??
          tools[name] ??
          (throw StateError(
            'Neither the ${game.id} game set nor the ${tools.id} tool set '
            'has $name, which a game needs.',
          )),
  ];

  /// The editor's trash: where it, and every change these commands make,
  /// put what they replace or remove — restorable from the editor.
  /// just_core_cli's transactions are told to use it (`trashRoot`).
  static const String editorTrash = '.editor_trash';

  /// The editor's machine-local folders, which a game's `.gitignore` lists:
  /// its backups, logs and deleted files.
  static const List<String> editorIgnores = [
    '.editor_backups/',
    '.editor_logs/',
    '$editorTrash/',
  ];

  /// macOS's entitlements for debug and profile builds — the editor's.
  static const String debugEntitlements =
      'macos/Runner/DebugProfile.entitlements';

  /// The files of template [template] for [names] on the game set [set]
  /// and the tool set [tools], by path: placeholders filled
  /// ([TemplateRenderer]), plus the first scene and the play order.
  /// [dependencies] and [devDependencies] are the pubspec lines for each
  /// section; [org] is the organisation the app ids use.
  ///
  /// Besides [TemplateRenderer]'s own, the placeholders are `{{dart}}` (from
  /// [set]), `{{set}}` (the tool set's id), `{{org}}`, and
  /// `{{dependencies}}` and `{{dev_dependencies}}` (each a line of its
  /// own). Throws
  /// [ArgumentError] for a template it doesn't have, or a title with a
  /// [ProjectNames.titleProblem].
  static Map<String, String> render(
    String template, {
    required ProjectNames names,
    required GameSet set,
    ToolSet tools = ToolSet.current,
    required List<String> dependencies,
    required List<String> devDependencies,
    String org = 'com.example',
  }) {
    final files = bundledTemplates[template];
    if (files == null) {
      throw ArgumentError.value(template, 'template', 'No such template');
    }
    return {
      ...TemplateRenderer.render(
        files,
        names: names,
        values: {'dart': set.dart, 'set': tools.id, 'org': org},
        lines: {
          'dependencies': dependencies,
          'dev_dependencies': devDependencies,
        },
      ),
      // Written as the editor's New Scene writes them, byte for byte.
      SceneManifest.scenePath('level_01'): SceneStarters.encode(
        SceneStarters.twoD('level_01'),
      ),
      SceneManifest.path: SceneManifest.encode(['level_01']),
    };
  }

  /// [text] (a `.gitignore`) with the editor's machine-local folders
  /// ([editorIgnores]) ignored; unchanged when it ignores them already.
  static String withEditorIgnores(String text) => GitIgnores.withEntries(
    text,
    editorIgnores,
    comment: "The editor's backups, logs and deleted files: machine-local.",
  );

  /// [text] (a macOS `.entitlements` plist) with the outgoing-network
  /// permission the editor's Asset Store needs; unchanged when it has it.
  static String withNetworkClient(String text) {
    const key = 'com.apple.security.network.client';
    if (text.contains(key)) return text;
    final nl = text.contains('\r\n') ? '\r\n' : '\n';
    final end = text.lastIndexOf('</dict>');
    if (end < 0) return text;
    return '${text.substring(0, end)}'
        '\t<!-- The editor\'s Asset Store downloads catalogs and items (debug'
        ' only: the editor never runs in a release build). -->$nl'
        '\t<key>$key</key>$nl\t<true/>$nl'
        '${text.substring(end)}';
  }

  /// Whether a project draws in 3D with Flutter GPU: one of its Dart files
  /// ([dartSources], the text of each) gives the engine a `Graphics3D`.
  /// Every game reaches just_graphics_engine through the engine, so its
  /// pubspec can't tell.
  static bool usesFlutterGpu(Iterable<String> dartSources) =>
      dartSources.any(_graphics3D.hasMatch);

  static final RegExp _graphics3D = RegExp(r'\bGraphics3D\s*\(');

  /// The runner files that switch Flutter GPU on, by path, each with what
  /// switches it on. Each leaves a file that has the switch as it is, and
  /// keeps its line endings.
  static const Map<String, String Function(String text)> flutterGpuRunners = {
    'windows/runner/main.cpp': withFlutterGpuWindows,
    'linux/runner/my_application.cc': withFlutterGpuLinux,
    'android/app/src/main/AndroidManifest.xml': withFlutterGpuAndroid,
    'ios/Runner/Info.plist': withFlutterGpuIos,
    'macos/Runner/Info.plist': withFlutterGpuMacos,
  };

  static String _nl(String text) => text.contains('\r\n') ? '\r\n' : '\n';

  /// [text] with [lines] after the first line matching [after], indented
  /// as that line is; unchanged when [after] is not there.
  static String _insertAfter(String text, Pattern after, List<String> lines) {
    final nl = _nl(text);
    final rows = text.split(nl);
    for (var i = 0; i < rows.length; i++) {
      if (!rows[i].contains(after)) continue;
      final indent = RegExp(r'^\s*').firstMatch(rows[i])!.group(0)!;
      rows.insertAll(i + 1, [for (final l in lines) '$indent$l']);
      return rows.join(nl);
    }
    return text;
  }

  /// A Windows runner's `main.cpp` with Flutter GPU on (release builds
  /// ignore the `--enable-flutter-gpu` flag).
  static String withFlutterGpuWindows(String text) {
    if (text.contains('set_enable_flutter_gpu')) return text;
    return _insertAfter(text, 'project.set_dart_entrypoint_arguments(', [
      '// 3D draws with Flutter GPU; release builds ignore --enable-flutter-gpu.',
      'project.set_enable_flutter_gpu(true);',
    ]);
  }

  /// A Linux runner's `my_application.cc` with Flutter GPU on.
  static String withFlutterGpuLinux(String text) {
    if (text.contains('fl_dart_project_set_enable_flutter_gpu')) return text;
    // After the entry-point arguments, which span two lines.
    final nl = _nl(text);
    final rows = text.split(nl);
    for (var i = 0; i < rows.length; i++) {
      if (!rows[i].contains('fl_dart_project_set_dart_entrypoint_arguments(')) {
        continue;
      }
      var end = i;
      while (end < rows.length - 1 && !rows[end].trimRight().endsWith(');')) {
        end++;
      }
      final indent = RegExp(r'^\s*').firstMatch(rows[i])!.group(0)!;
      rows.insertAll(end + 1, [
        '$indent// 3D draws with Flutter GPU.',
        '${indent}fl_dart_project_set_enable_flutter_gpu(project, TRUE);',
      ]);
      return rows.join(nl);
    }
    return text;
  }

  /// An Android manifest with Impeller on Vulkan and Flutter GPU on.
  /// Devices without Vulkan fall back to OpenGL ES, where the game shows
  /// that 3D is off.
  static String withFlutterGpuAndroid(String text) {
    if (text.contains('EnableFlutterGPU')) return text;
    final nl = _nl(text);
    final end = text.lastIndexOf('</application>');
    if (end < 0) return text;
    final lineStart = text.lastIndexOf(nl, end) + nl.length;
    final indent = text.substring(lineStart, end);
    final inner = '$indent    ';
    String meta(String name, String value) =>
        '$inner<meta-data$nl$inner    android:name="$name"$nl$inner    android:value="$value" />$nl';
    return '${text.substring(0, lineStart)}'
        '$inner<!-- 3D draws with Flutter GPU, on Impeller\'s Vulkan backend. Devices$nl'
        '$inner     without Vulkan fall back to OpenGL ES, where 3D is turned off. -->$nl'
        '${meta('io.flutter.embedding.android.EnableImpeller', 'true')}'
        '${meta('io.flutter.embedding.android.EnableFlutterGPU', 'true')}'
        '${meta('io.flutter.embedding.android.ImpellerBackend', 'vulkan')}'
        '${text.substring(lineStart)}';
  }

  static String _plistKeys(String text, List<String> keys) {
    final missing = [
      for (final k in keys)
        if (!text.contains('<key>$k</key>')) k,
    ];
    if (missing.isEmpty) return text;
    final nl = _nl(text);
    final end = text.lastIndexOf('</dict>');
    if (end < 0) return text;
    return '${text.substring(0, end)}'
        '${[for (final k in missing) '\t<key>$k</key>$nl\t<true/>$nl'].join()}'
        '${text.substring(end)}';
  }

  /// An iOS `Info.plist` with Flutter GPU on (Impeller is iOS's default).
  static String withFlutterGpuIos(String text) =>
      _plistKeys(text, ['FLTEnableFlutterGPU']);

  /// A macOS `Info.plist` with Impeller and Flutter GPU on.
  static String withFlutterGpuMacos(String text) =>
      _plistKeys(text, ['FLTEnableImpeller', 'FLTEnableFlutterGPU']);
}
