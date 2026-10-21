/// `just game scene`: the project's levels, without opening the editor.
library;

import 'dart:convert';
import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_core_cli/project.dart';
import 'package:just_game_engine_formats/just_game_engine_formats.dart';

import '../create/game_template.dart';
import '../project/game_project.dart';
import 'migration_safety.dart';

/// `just game scene new|list|rename|delete|order|migrate|validate`.
final class SceneCommand extends JustCommand {
  /// The command and its subcommands.
  SceneCommand() {
    for (final c in <JustCommand>[
      _SceneList(),
      _SceneNew(),
      _SceneRename(),
      _SceneDelete(),
      _SceneOrder(),
      _SceneMigrate(),
      _SceneValidate(),
    ]) {
      addSubcommand(c);
    }
  }

  @override
  String get name => 'scene';

  @override
  String get description =>
      'The levels in assets/scenes/: make, rename, delete, order, migrate and '
      'check them — the files the editor saves, written as it writes them.';
}

/// What every scene command shares.
abstract class _SceneBase extends JustCommand {
  _SceneBase({bool writes = true}) {
    if (writes) {
      argParser.addFlag(
        'force',
        negatable: false,
        help:
            'Write even though the editor has the project open (it would '
            'save over the change).',
      );
    }
  }

  JustProject get project => requireProject();

  /// The scene names on disk, sorted.
  List<String> onDisk(JustProject p) {
    final dir = p.dir(SceneManifest.directory);
    if (!dir.existsSync()) return [];
    const suffix = '.scene.json';
    return [
      // Files only: a folder named like a scene is none.
      for (final f in dir.listSync().whereType<File>())
        if (f.path.endsWith(suffix))
          f.uri.pathSegments.last.substring(
            0,
            f.uri.pathSegments.last.length - suffix.length,
          ),
    ]..sort();
  }

  /// The scenes the arguments name, each one on disk, or every scene on
  /// disk when they name none. Throws [CommandFailure] for a name that is
  /// not a scene: only those, never a path made from a name.
  List<String> chosen(JustProject p) {
    final disk = onDisk(p);
    if (rest.isEmpty) return disk;
    final missing = [
      for (final n in rest)
        if (!disk.contains(n)) n,
    ];
    if (missing.isNotEmpty) {
      throw CommandFailure('No such scene: ${missing.join(', ')}.');
    }
    return rest;
  }

  /// The play order in `scenes.json`.
  List<String> listed(JustProject p) =>
      SceneManifest.parse(p.readText(SceneManifest.path) ?? '');

  /// Refuses while the editor has [p] open, unless `--force`.
  void guard(JustProject p) {
    if (argResults!.flag('force')) return;
    if (p.editorIsOpen()) {
      throw const CommandFailure(
        'The editor has this project open: it holds the scenes in memory and '
        'would save over this change. Close it first, or make the change in '
        'the editor (or pass --force).',
      );
    }
  }

  /// Runs [change] in a transaction under the project lock: all of it, or
  /// none of it.
  void change(JustProject p, void Function(ProjectTransaction txn) change) {
    final lock = ProjectLock.acquire(p);
    try {
      ProjectTransaction.recover(p, trashRoot: GameTemplate.editorTrash);
      final txn = ProjectTransaction.begin(
        p,
        trash: 'scenes',
        trashRoot: GameTemplate.editorTrash,
      );
      try {
        change(txn);
        txn.commit();
      } on Object {
        txn.rollBack();
        rethrow;
      }
    } finally {
      lock.release();
    }
  }

  /// [name]'s scene, decoded. Throws [CommandFailure] when it is missing or
  /// broken.
  Map<String, dynamic> read(JustProject p, String name) {
    final path = SceneManifest.scenePath(name);
    final text = p.readText(path);
    if (text == null) throw CommandFailure('There is no scene "$name".');
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw CommandFailure('$path is not valid JSON: ${e.message}');
    }
    if (json is! Map<String, dynamic>) {
      throw CommandFailure('$path is not a scene.');
    }
    return json;
  }

  static String encode(Map<String, dynamic> scene) =>
      const JsonEncoder.withIndent('  ').convert(scene);
}

final class _SceneList extends _SceneBase {
  _SceneList() : super(writes: false);

  @override
  String get name => 'list';

  @override
  String get description =>
      'The scenes: the play order first, then any not in it.';

  @override
  Future<int> run() async {
    final p = project;
    final order = listed(p);
    final files = onDisk(p).toSet();
    final rows = <Map<String, Object?>>[];
    for (final name in [...order, ...files.where((f) => !order.contains(f))]) {
      final row = <String, Object?>{
        'name': name,
        'listed': order.contains(name),
        'exists': files.contains(name),
      };
      if (files.contains(name)) {
        try {
          final scene = read(p, name);
          row
            ..['mode'] = scene['mode'] ?? '2d'
            ..['version'] = SceneFormat.versionOf(scene)
            ..['entities'] = (scene['entities'] as List?)?.length ?? 0;
        } on Object catch (e) {
          row['error'] = '$e';
        }
      }
      rows.add(row);
      final where = row['listed'] == true
          ? '${order.indexOf(name) + 1}.'
          : ' -';
      final detail = row['error'] != null
          ? 'unreadable'
          : row['exists'] == false
          ? 'listed, but its file is missing'
          : '${row['mode']}, ${row['entities']} entities'
                '${row['version'] == SceneFormat.current ? '' : ', format v${row['version']}'}';
      output.line('$where $name  ($detail)');
    }
    if (rows.isEmpty) {
      output.line(
        'No scenes yet: `${context.invokedAs} game scene new level_01`.',
      );
    }
    output.result = rows;
    return 0;
  }
}

final class _SceneNew extends _SceneBase {
  _SceneNew() {
    argParser
      ..addFlag('3d', negatable: false, help: 'A 3-D scene.')
      ..addOption('after', help: 'Where it goes in the play order.')
      ..addFlag(
        'unlisted',
        negatable: false,
        help: 'Leave it out of the play order.',
      );
  }

  @override
  String get name => 'new';

  @override
  String get description =>
      'A new scene, as the editor makes one: a camera and a player spawn.';

  @override
  String get invocation =>
      '${context.invokedAs} game scene new [<name>] [options]';

  @override
  Future<int> run() async {
    final p = project;
    final existing = onDisk(p);
    final order = listed(p);
    final after = argResults!.option('after');
    if (rest.length > 1) throw const UsageFailure('new takes one name.');
    final name = rest.isEmpty
        ? SceneNames.suggest(existing, after: after ?? order.lastOrNull)
        : rest.single;
    final problem = SceneNames.problem(name, existing: existing);
    if (problem != null) throw CommandFailure(problem);
    if (after != null && !order.contains(after)) {
      throw CommandFailure('"$after" is not in the play order.');
    }
    guard(p);
    final scene = SceneStarters.forMode(
      name,
      mode: argResults!.flag('3d') ? '3d' : '2d',
    );
    final next = [...order];
    if (!argResults!.flag('unlisted')) {
      after == null
          ? next.add(name)
          : next.insert(next.indexOf(after) + 1, name);
    }
    change(p, (txn) {
      txn.write(SceneManifest.scenePath(name), SceneStarters.encode(scene));
      if (next.length != order.length) {
        txn.write(SceneManifest.path, SceneManifest.encode(next));
      }
    });
    output
      ..result = {
        'name': name,
        'path': SceneManifest.scenePath(name),
        'order': next,
      }
      ..line('Made ${SceneManifest.scenePath(name)}.');
    return 0;
  }
}

final class _SceneRename extends _SceneBase {
  @override
  String get name => 'rename';

  @override
  String get description =>
      'Rename a scene: its file, its name inside, and its place in the play '
      'order.';

  @override
  String get invocation => '${context.invokedAs} game scene rename <old> <new>';

  @override
  Future<int> run() async {
    if (rest.length != 2) throw const UsageFailure('rename takes two names.');
    final [from, to] = rest;
    final p = project;
    final existing = onDisk(p);
    if (!existing.contains(from)) {
      throw CommandFailure('There is no scene "$from".');
    }
    if (to == from) throw CommandFailure('The scene is called "$to" already.');
    // Only the scene itself is out of the way: on a disk that tells case
    // apart, another scene may differ from it only in case.
    final problem = SceneNames.problem(
      to,
      existing: existing.where((e) => e != from),
    );
    if (problem != null) throw CommandFailure(problem);
    guard(p);
    final scene = read(p, from)..['name'] = to;
    final order = [for (final n in listed(p)) n == from ? to : n];
    final fromPath = SceneManifest.scenePath(from);
    final toPath = SceneManifest.scenePath(to);
    // A rename in case alone, on a disk that ignores case (Windows, macOS):
    // both names are one file. Rewritten under its old name (backed up),
    // then renamed — never written under one name and deleted under the
    // other. A rollback writes the old name back, case and all.
    final sameFile =
        from.toLowerCase() == to.toLowerCase() && p.file(toPath).existsSync();
    change(p, (txn) {
      if (sameFile) {
        txn.write(fromPath, _SceneBase.encode(scene));
        retryOnLock(() => p.file(fromPath).renameSync(p.path(toPath)));
      } else {
        txn
          ..write(toPath, _SceneBase.encode(scene))
          ..delete(fromPath);
      }
      txn.write(SceneManifest.path, SceneManifest.encode(order));
    });
    output
      ..result = {'from': from, 'to': to}
      ..line('Renamed $from to $to.')
      ..info(
        'Anything that names "$from" — a level exit, a script — still does: '
        'search the project for it.',
      );
    return 0;
  }
}

final class _SceneDelete extends _SceneBase {
  @override
  String get name => 'delete';

  @override
  String get description =>
      'Delete a scene (a copy goes to .editor_trash/scenes/) and take it out '
      'of the play order.';

  @override
  String get invocation => '${context.invokedAs} game scene delete <name>';

  @override
  Future<int> run() async {
    final name = singleArgument('a scene name');
    final p = project;
    if (!onDisk(p).contains(name)) {
      throw CommandFailure('There is no scene "$name".');
    }
    final path = SceneManifest.scenePath(name);
    final text = p.readText(path);
    if (text == null) throw CommandFailure('There is no scene "$name".');
    guard(p);
    if (!confirm('Delete $path?')) return 1;
    final order = listed(p)..remove(name);
    change(p, (txn) {
      txn
        ..write(
          '${GameTemplate.editorTrash}/scenes/${txn.stamp}/$name.scene.json',
          text,
        )
        ..delete(path)
        ..write(SceneManifest.path, SceneManifest.encode(order));
    });
    output
      ..result = {'deleted': name}
      ..line('Deleted $name (a copy is in .editor_trash/scenes/).');
    return 0;
  }
}

final class _SceneOrder extends _SceneBase {
  @override
  String get name => 'order';

  @override
  String get description =>
      'Set the play order: the scenes given, in that order. The first is '
      'where the game starts; one left out stays on disk, unlisted.';

  @override
  String get invocation => '${context.invokedAs} game scene order <name>...';

  @override
  Future<int> run() async {
    if (rest.isEmpty) throw const UsageFailure('order needs the scene names.');
    final p = project;
    final existing = onDisk(p);
    final missing = rest.where((n) => !existing.contains(n)).toList();
    if (missing.isNotEmpty) {
      throw CommandFailure('No such scene: ${missing.join(', ')}.');
    }
    if (rest.toSet().length != rest.length) {
      throw const CommandFailure('A scene is named twice.');
    }
    guard(p);
    change(
      p,
      (txn) => txn.write(SceneManifest.path, SceneManifest.encode(rest)),
    );
    output
      ..result = {'order': rest}
      ..line('Play order: ${rest.join(', ')}.');
    return 0;
  }
}

final class _SceneMigrate extends _SceneBase {
  _SceneMigrate() {
    argParser.addFlag(
      'engine-only',
      negatable: false,
      help:
          "Migrate with the engine's rules alone, though a kit may have its "
          'own (see the message without it).',
    );
  }

  @override
  String get name => 'migrate';

  @override
  String get description =>
      'Rewrite scenes saved in an older format in the current one '
      '(v${SceneFormat.current}). The editor migrates them as it loads them '
      'anyway; this makes the files say so.';

  @override
  String get invocation =>
      '${context.invokedAs} game scene migrate [<name>...]';

  @override
  Future<int> run() async {
    final p = project;
    final names = chosen(p);
    final todo = <String, Map<String, dynamic>>{};
    final notes = <String>[];
    final newer = <String>[];
    for (final n in names) {
      final scene = read(p, n);
      // One scene that can't be read stops it all, named: nothing is
      // written yet.
      try {
        final version = SceneFormat.versionOf(scene);
        if (version > SceneFormat.current) {
          newer.add(n);
          output.warn(
            '$n is from a newer engine (format v$version; this one writes '
            'v${SceneFormat.current}): left as it is.',
          );
          continue;
        }
        if (version == SceneFormat.current) continue;
        final result = SceneFormat.migrateWithReport(scene);
        todo[n] = result.scene;
        notes.addAll(result.notes.map((m) => '$n: $m'));
      } on FormatException catch (e) {
        throw CommandFailure(
          'Nothing was migrated: ${SceneManifest.scenePath(n)}: ${e.message}',
        );
      }
    }
    if (todo.isEmpty) {
      output
        ..result = {'migrated': <String>[], 'newer': newer}
        ..line(
          newer.isEmpty
              ? 'Every scene is in format v${SceneFormat.current}.'
              : 'No scene to migrate.',
        );
      return 0;
    }
    MigrationSafety.check(
      p,
      engineOnly: argResults!.flag('engine-only'),
      retry: '${context.invokedAs} game scene migrate --engine-only',
    );
    guard(p);
    change(p, (txn) {
      todo.forEach(
        (n, s) => txn.write(SceneManifest.scenePath(n), _SceneBase.encode(s)),
      );
    });
    for (final n in notes) {
      output.info('  $n');
    }
    output
      ..result = {
        'migrated': todo.keys.toList(),
        'notes': notes,
        'newer': newer,
      }
      ..line(
        'Migrated ${todo.keys.join(', ')} to format v${SceneFormat.current}.',
      );
    return 0;
  }
}

final class _SceneValidate extends _SceneBase {
  _SceneValidate() : super(writes: false);

  @override
  String get name => 'validate';

  @override
  String get description =>
      'Check scenes without changing them: they parse, their format is one '
      'this engine reads, entity names are unique and parents exist.';

  @override
  String get invocation =>
      '${context.invokedAs} game scene validate [<name>...]';

  @override
  Future<int> run() async {
    final p = project;
    final disk = onDisk(p);
    final names = rest.isEmpty ? disk : rest;
    final problems = <String, List<String>>{};
    for (final n in names) {
      final found = problems[n] = [];
      if (!disk.contains(n)) {
        found.add('There is no scene "$n".');
        continue;
      }
      try {
        final migrated = SceneFormat.migrate(read(p, n));
        final entities = switch (migrated['entities']) {
          null => const <Object?>[],
          final List<Object?> list => list,
          _ => null,
        };
        if (entities == null) {
          found.add('its "entities" is not a list');
          continue;
        }
        final seen = <String>{};
        for (final e in entities) {
          if (e is! Map) {
            found.add('an entity that is not an object');
            continue;
          }
          final name = e['name'];
          if (name is! String || name.isEmpty) {
            found.add('an entity with no name');
          } else if (!seen.add(name)) {
            found.add('two entities called "$name"');
          }
          // An instance of a prefab file holds its prefab, not components.
          final prefab = e['prefab'];
          if (prefab != null) {
            if (prefab is! Map || prefab['path'] is! String || (prefab['path'] as String).isEmpty) {
              found.add('"$name" is an instance of no prefab file');
            }
            continue;
          }
          final components = e['components'];
          if (components is! List) {
            found.add('"$name" has no component list');
            continue;
          }
          for (final c in components) {
            if (c is! Map || c['type'] is! String) {
              found.add('"$name" has a component without a type');
            }
          }
        }
        for (final e in entities.whereType<Map<String, dynamic>>()) {
          final parent = e['parentName'];
          if (parent is String && !seen.contains(parent)) {
            found.add(
              '"${e['name']}" has a parent, "$parent", that is not there',
            );
          }
        }
      } on UnsupportedFormatVersionException catch (e) {
        found.add(e.message);
      } on CommandFailure catch (e) {
        found.add(e.message);
      } on FormatException catch (e) {
        found.add(e.message);
      }
    }
    final order = listed(p);
    final missing = order.where((n) => !disk.contains(n)).toList();
    for (final n in names) {
      final f = problems[n]!;
      output.line(f.isEmpty ? 'ok  $n' : 'x   $n: ${f.join('; ')}');
    }
    for (final m in missing) {
      output.line('x   $m is in the play order, but has no file.');
    }
    output.result = {'scenes': problems, 'missing': missing};
    return problems.values.any((f) => f.isNotEmpty) || missing.isNotEmpty
        ? 1
        : 0;
  }
}
