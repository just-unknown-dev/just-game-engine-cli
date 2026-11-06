/// `just game doctor`: what in a game's setup would ship the editor, or
/// keep it from working.
library;

import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_core_cli/project.dart';
import 'package:meta/meta.dart';

import '../game/game.dart';
import '../project/project.dart';
import '../release/release.dart';

/// `just game doctor`: the game's half of `just doctor` (its `doctor`
/// hook) — the editor kept to debug builds, the game's entry point free of
/// editor imports, no editor package among the dependencies that ship, the
/// editor's machine-local folders ignored by git, macOS's permission for
/// the editor's Asset Store to connect, Flutter and Dart against the
/// engine's floors and the engine's packages against its [GameSet], and the
/// store items linked to checkouts that are still there.
///
/// The entry point's imports are judged by the game's release rules
/// ([ProjectGame.releaseRules]), as `game check` judges them; only its own
/// imports are read here (`game check` walks them all).
@internal
final class GameDoctorCommand extends JustCommand {
  @override
  String get name => 'doctor';

  @override
  String get description =>
      "Check the game's setup: the editor kept out of releases, git ignores, "
      "the macOS entitlement, the SDKs and the engine's versions, and the "
      'store links. `just doctor` runs it.';

  @override
  Future<int> run() async {
    final project = requireProject();
    final findings = await check(project);
    final problem = output.findings(findings);
    output.result = {
      'findings': [for (final f in findings) f.toJson()],
    };
    if (findings.isEmpty) output.line('ok  Nothing to check here.');
    return problem ? 1 : 0;
  }

  /// What is wrong with [project]'s game setup, and what is right.
  Future<List<Finding>> check(JustProject project) async {
    final out = <Finding>[];
    final file = project.readProjectFile();
    final editorEntry = GameEntries.editor(file);
    final gameEntry = GameEntries.game(file);

    final editor = project.readText(editorEntry);
    if (editor != null) {
      out.add(
        RegExp(r'if\s*\(\s*kDebugMode\s*\)').hasMatch(editor)
            ? Finding(
                Severity.ok,
                '$editorEntry keeps the editor to debug builds.',
              )
            : Finding(
                Severity.problem,
                '$editorEntry has no `if (kDebugMode)` around the editor.',
                fix:
                    'Wrap the editor in `if (kDebugMode) { ... } else { '
                    'runApp(game) }`: an early return still compiles the '
                    'editor into a release.',
              ),
      );
    }
    final game = project.readText(gameEntry) ?? '';
    final editorImports = _editorImports(project, gameEntry, game);
    if (editorImports.isNotEmpty) {
      out.add(
        Finding(
          Severity.problem,
          '$gameEntry imports editor code, which would ship '
          '(${editorImports.join(', ')}).',
          fix: 'Only $editorEntry may import the editor.',
        ),
      );
    }
    final pubspec = project.readText(JustProject.pubspec) ?? '';
    final dependencies = _dependencies(pubspec);
    if (dependencies == null) {
      out.add(
        const Finding(
          Severity.warning,
          "pubspec.yaml's dependencies could not be read, so they were not "
          'checked for editor packages.',
        ),
      );
    }
    for (final name in dependencies ?? const <String>[]) {
      if (name.endsWith('_editor') &&
          name.startsWith('just_') &&
          name != 'just_ui_editor') {
        out.add(
          Finding(
            Severity.problem,
            '$name is a dependency, so its native plugins ship.',
            fix: 'Move it to dev_dependencies.',
          ),
        );
      }
    }

    // As git sees it: `/.editor_trash/`, `.editor_trash` and an ignore
    // further up all count, not only the lines the template writes.
    final missing = [
      for (final entry in GameTemplate.editorIgnores)
        if (!await OverridesTarget.isGitIgnored(
          project,
          // A file in the folder: a folder's pattern (`name/`) matches it.
          entry.endsWith('/') ? '${entry}probe' : entry,
        ))
          entry,
    ];
    if (missing.isNotEmpty) {
      out.add(
        Finding(
          Severity.warning,
          ".gitignore does not ignore the editor's machine-local files "
          '(${missing.join(', ')}).',
          fix: 'Add them to .gitignore.',
        ),
      );
    }

    final entitlements = project.readText(GameTemplate.debugEntitlements);
    if (entitlements != null &&
        GameTemplate.withNetworkClient(entitlements) != entitlements) {
      out.add(
        const Finding(
          Severity.warning,
          "macOS: the editor's Asset Store can't connect.",
          fix:
              'Add com.apple.security.network.client to '
              '${GameTemplate.debugEntitlements}.',
        ),
      );
    }
    return [...out, ..._versions(project), ..._storeLinks(project)];
  }

  /// Flutter and Dart against the engine's floors, and the engine's
  /// packages against what pub resolved — from [GameSet.current].
  List<Finding> _versions(JustProject project) {
    const set = GameSet.current;
    final out = <Finding>[];
    final sdk = SdkLocator.locate(
      project.root,
      environment: context.environment,
    );
    if (sdk != null) {
      for (final (what, found, needs) in [
        ('Flutter', sdk.flutterVersion, set.flutter),
        ('Dart', sdk.dartVersion, set.dart),
      ]) {
        final v = Version.tryParse(found ?? '');
        final want = VersionConstraint.tryParse(needs);
        if (v == null || want == null) {
          out.add(
            Finding(Severity.warning, "$what's version could not be read."),
          );
          continue;
        }
        out.add(
          want.allows(v)
              ? Finding(Severity.ok, '$what $v (the engine needs $needs).')
              : Finding(
                  Severity.problem,
                  '$what $v is too old: the engine needs $needs.',
                  fix: 'Run `flutter upgrade`.',
                ),
        );
      }
    }
    final config = PackageConfig.read(project.root);
    if (config == null) return out; // `just doctor` says so.
    for (final p in set.packages) {
      final v = config.packages[p.name]?.version;
      if (v == null || p.versions.allows(v)) continue;
      // Past the set: `upgrade` never moves a game back (GameSet.bump).
      final floor = p.versions.min;
      final ahead = floor != null && v > floor;
      out.add(
        ahead
            ? Finding(
                Severity.warning,
                '${p.name} is $v, newer than the ${set.id} game set '
                '(${p.constraint}) this just_game_engine_cli knows.',
                fix:
                    'Move just_game_engine_cli on in dev_dependencies: a '
                    'newer one knows newer engines.',
              )
            : Finding(
                Severity.warning,
                '${p.name} is $v; the ${set.id} game set has ${p.constraint}.',
                fix: '`${context.invokedAs} upgrade` moves the project to it.',
              ),
      );
    }
    return out;
  }

  /// The store items `just_store.lock.json` lists as linked to a checkout
  /// that is no longer there.
  List<Finding> _storeLinks(JustProject project) {
    final lock = project.readText('just_store.lock.json');
    if (lock == null) return const [];
    final out = <Finding>[];
    try {
      final items = JsonFields.parse(lock).optObject('items');
      for (final id in items?.keys ?? const <String>[]) {
        final item = items!.object(id);
        final path = item.optString('path');
        if (item.optString('origin') == 'linked' &&
            path != null &&
            !Directory(
              File(path).isAbsolute ? path : project.path(path),
            ).existsSync()) {
          out.add(
            Finding(
              Severity.problem,
              '$id is linked to $path, which is not there.',
              fix:
                  '`${context.invokedAs} store unlink $id`, or check the '
                  'checkout out again.',
            ),
          );
        }
      }
    } on JsonFormatException catch (e) {
      out.add(Finding(Severity.problem, 'just_store.lock.json: $e'));
    }
    return out;
  }

  /// The editor code [source], the game's entry point at [entry], imports
  /// itself: what the game's release rules forbid
  /// ([ReleaseRules.forbids]), and the project's own `lib/editor/`.
  static List<String> _editorImports(
    JustProject project,
    String entry,
    String source,
  ) {
    final rules = project.releaseRules();
    final from = Uri.file(project.path(entry));
    final editorFolder = Uri.directory(
      project.path(ReleaseRules.appEditorFolder),
    ).path;
    String folded(String path) =>
        Platform.isWindows || Platform.isMacOS ? path.toLowerCase() : path;
    return [
      for (final uri in ReleaseImports.dartUrisIn(source))
        if (rules.forbids(uri) ||
            (!uri.startsWith('package:') &&
                folded(
                  from.resolve(uri).path,
                ).startsWith(folded(editorFolder))))
          uri,
    ];
  }

  /// The names in [pubspec]'s top-level `dependencies`, however they are
  /// indented or written; null when the pubspec can't be read as one.
  static List<String>? _dependencies(String pubspec) {
    try {
      final editor = PubspecEditor.parse(
        pubspec,
        marker: ManagedBlock.devLinks,
      );
      return [
        ...editor.unmanaged('dependencies').keys,
        ...editor.managed('dependencies').keys,
      ];
    } on PubspecEditException {
      return null;
    }
  }
}
