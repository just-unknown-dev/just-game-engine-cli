/// `just game upgrade`: the engine's packages moved to this version's set.
library;

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_core_cli/project.dart';

import '../create/game_set.dart';

/// `just game upgrade [--check] [--yes]`: the constraints of the engine's
/// packages in `pubspec.yaml` moved to the versions this
/// just_game_engine_cli carries ([GameSet.current]) — the game's `upgrade`
/// hook.
///
/// Each is a one-line bump of an entry a person wrote ([GameSet.bump]);
/// blocks (a git source, a path), tools' managed blocks and packages the
/// game is ahead of the set on stay as they are. It writes `pubspec.yaml`
/// alone, never runs `pub get` and takes no project lock: `just upgrade` runs it inside its own transaction and
/// fetches the packages itself. `--check` changes nothing and says what
/// would move. Its result: `{set, packages: {name: {from, to}}, changed}`.
final class GameUpgradeCommand extends JustCommand {
  /// The command and its options.
  GameUpgradeCommand() {
    argParser.addFlag(
      'check',
      negatable: false,
      help: 'Change nothing: say what would move.',
    );
  }

  @override
  String get name => 'upgrade';

  @override
  String get description =>
      "Move the engine's packages in pubspec.yaml to the versions this "
      'just_game_engine_cli carries (no pub get). `just upgrade` runs it, '
      'and fetches the packages.';

  @override
  Future<int> run() async {
    final project = requireProject();
    const set = GameSet.current;
    final pubspec =
        project.readText(JustProject.pubspec) ??
        (throw const CommandFailure('The project has no pubspec.yaml.'));
    final resolved = {
      for (final p
          in PackageConfig.read(project.root)?.packages.values ??
              const <ResolvedPackage>[])
        p.name: ?p.version,
    };
    final (next, bumps) = set.bump(pubspec, resolved: resolved);
    for (final e in bumps.entries) {
      output.line('  ~ ${e.key}  ${e.value['from']} -> ${e.value['to']}');
    }
    final result = <String, Object?>{
      'set': set.id,
      'packages': bumps,
      'changed': false,
    };
    output.result = result;
    if (bumps.isEmpty) {
      output.line("No engine package needs moving to the ${set.id} set.");
      return 0;
    }
    if (argResults!.flag('check')) {
      output.line('${bumps.length} packages would move to the ${set.id} set.');
      return 0;
    }
    if (!confirm('Move ${bumps.length} packages in pubspec.yaml?')) return 1;
    writeTextAtomic(project.file(JustProject.pubspec), next);
    result['changed'] = true;
    output
      ..info(
        'Store items keep their versions: `${context.invokedAs} store update` '
        'moves them on.',
      )
      ..line(
        'Moved ${bumps.length} packages to the ${set.id} set. Fetch them with '
        '`flutter pub get` (`${context.invokedAs} upgrade` does it all).',
      );
    return 0;
  }
}
