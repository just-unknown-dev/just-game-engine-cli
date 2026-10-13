/// `just game migrate`: the game's saved files in the current formats.
library;

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_core_cli/project.dart';

import '../create/game_template.dart';
import '../project/game_project.dart';
import '../release/formats_check.dart';
import 'migration_safety.dart';

/// `just game migrate [--check] [--engine-only] [--force]`: every scene,
/// timeline and animator graph under `assets/` saved in an older format,
/// rewritten in the current one as the editor writes it — all of them in
/// one transaction, or none.
///
/// It is the game's `migrate` hook: `just upgrade` runs it with `--check`
/// before it changes anything, and for real once the project is on the new
/// set. `--check` changes nothing; it fails, saying why, when a migration
/// could not run now: while the editor has the project open (the packages
/// an upgrade brings may have newer formats, whatever the files are now),
/// or when old files would be rewritten past a kit that has rules of its
/// own ([MigrationSafety]). Without `--check`, an open editor stops it only
/// when there are files to rewrite. With `--json`, its result's `migrated`
/// lists what it rewrote: `just upgrade` reads it.
final class GameMigrateCommand extends JustCommand {
  /// The command and its options.
  GameMigrateCommand() {
    argParser
      ..addFlag(
        'check',
        negatable: false,
        help:
            'Change nothing: fail, saying why, when a migration could not '
            'run now (`just upgrade` asks this first).',
      )
      ..addFlag(
        'engine-only',
        negatable: false,
        help:
            "Rewrite old files with the engine's rules alone, though a kit "
            'may have its own.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Go ahead though the editor has the project open.',
      );
  }

  @override
  String get name => 'migrate';

  @override
  String get description =>
      'Rewrite the scenes, timelines and animator graphs saved in an older '
      'format in the current one. `just upgrade` runs it.';

  @override
  Future<int> run() async {
    final project = requireProject();
    final check = argResults!.flag('check');
    final engineOnly = argResults!.flag('engine-only');
    final force = argResults!.flag('force');
    final old = [
      for (final f in project.checkFormats())
        if (f.error == null &&
            f.old &&
            FormatsCheck.migratable.contains(f.kind))
          f,
    ];
    for (final f in old) {
      output.line('  ~ ${f.path}  ${f.kind} v${f.version} -> v${f.current}');
    }
    // The message's command, in backquotes: from `just upgrade`, migrate on
    // its own first.
    final retry = check
        ? '${context.invokedAs} game migrate --engine-only` first, then '
              '`${context.invokedAs} upgrade'
        : '${context.invokedAs} game migrate --engine-only';

    if (check) {
      if (!force && project.editorIsOpen()) {
        throw const CommandFailure(
          'The editor has this project open: it would save its scenes over '
          'migrated ones, and the packages an upgrade fetches change under '
          'it. Close it first.',
        );
      }
      if (old.isNotEmpty) {
        MigrationSafety.check(project, engineOnly: engineOnly, retry: retry);
      }
      output
        ..result = {
          'check': true,
          'old': [for (final f in old) f.path],
        }
        ..line(
          old.isEmpty
              ? 'Nothing to migrate now; a migration can run.'
              : 'A migration can run: ${old.length} old files.',
        );
      return 0;
    }

    if (old.isEmpty) {
      output
        ..result = {'migrated': <String>[]}
        ..line('Every saved file is in its current format.');
      return 0;
    }
    MigrationSafety.check(project, engineOnly: engineOnly, retry: retry);
    if (!force && project.editorIsOpen()) {
      throw const CommandFailure(
        'The editor has this project open and would save its scenes over '
        'the migrated ones. Close it first (or pass --force).',
      );
    }
    if (!confirm('Rewrite ${old.length} files in the current formats?')) {
      return 1;
    }
    final lock = ProjectLock.acquire(project);
    try {
      ProjectTransaction.recover(project, trashRoot: GameTemplate.editorTrash);
      final txn = ProjectTransaction.begin(
        project,
        trash: 'migrate',
        trashRoot: GameTemplate.editorTrash,
      );
      try {
        for (final f in old) {
          txn.write(
            f.path,
            FormatsCheck.migrated(f.kind, project.readText(f.path)!),
          );
        }
        txn.commit();
      } on Object {
        txn.rollBack();
        rethrow;
      }
    } finally {
      lock.release();
    }
    output
      ..result = {
        'migrated': [for (final f in old) f.path],
      }
      ..line('Migrated ${old.length} files to their current formats.');
    return 0;
  }
}
