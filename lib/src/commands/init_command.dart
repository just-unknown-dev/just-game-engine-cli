/// `just game init`: the game's `create` hook.
library;

import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_core_cli/project.dart';

import '../create/game_set.dart';
import '../create/game_template.dart';

/// `just game init`: what `just create` runs in a project it has just made
/// (the game's `create` hook) to make it a game — hidden from the help,
/// since `just create` is the way to start one.
///
/// It lays the game template over what `flutter create` wrote (the engine,
/// the tools and the editor in the pubspec, a first level, the editor's
/// git ignores, macOS's network permission), fetches the packages, adds the
/// editor through the Asset Store (`store link` for `--local` checkouts,
/// `store install` otherwise), lays a store `--template` over it all, and
/// switches Flutter GPU on in the runners of a game that draws in 3D.
///
/// The pubspec it writes keeps just_core_cli and just_game_engine_cli in
/// `dev_dependencies`, one line each, as `just create` added them, so
/// `just upgrade` moves them. The store runs only when it may
/// ([runTrustedPlugin]): under just_core_cli's trust rule (`PluginTrust`),
/// or once allowed.
final class GameInitCommand extends JustCommand {
  /// The command and its options: those `just create` passes.
  GameInitCommand() {
    argParser
      ..addOption(
        'title',
        help: "The game's name as players see it (default: just.json's).",
      )
      ..addOption(
        'org',
        defaultsTo: 'com.example',
        help: 'The reverse-domain organisation the app ids use.',
      )
      ..addOption(
        'platforms',
        help:
            'The platforms `just create` made; the runner files on disk are '
            'what count.',
      )
      ..addOption(
        'template',
        abbr: 't',
        defaultsTo: GameTemplate.empty,
        help: 'What to start from: "empty", or a template from the store.',
      )
      ..addMultiOption(
        'source',
        valueHelp: 'catalog',
        help: 'A store catalog to find a --template in; repeat for several.',
      )
      ..addOption(
        'local',
        valueHelp: 'packages folder',
        help:
            'The local checkouts `just create --local` linked: their store '
            'items are registered as linked instead of installed.',
      );
  }

  @override
  String get name => 'init';

  @override
  String get description =>
      'Make the project a game (what `just create` runs: its `create` hook).';

  @override
  bool get hidden => true;

  @override
  Future<int> run() async {
    final project = requireProject();
    final pubspec = project.readText(JustProject.pubspec) ?? '';
    final name =
        RegExp(
          r'^name:\s*(\S+)',
          multiLine: true,
        ).firstMatch(pubspec)?.group(1) ??
        project.root.split('/').last;
    final file = project.readProjectFile();
    final names = ProjectNames(
      name,
      title: argResults!.option('title') ?? file.title,
    );
    final titleProblem = ProjectNames.titleProblem(names.title);
    if (titleProblem != null) throw UsageFailure('--title: $titleProblem');
    // The engine's versions are this package's; the tools' are the tool
    // set's that `just create` recorded.
    const set = GameSet.current;
    final toolSet = file.set;
    final tools =
        (toolSet == null ? null : ToolSet.named(toolSet)) ?? ToolSet.current;
    final template = argResults!.option('template')!;
    // A template that isn't built in comes from the Asset Store: the empty
    // game is made first, and the store's template laid over it.
    final fromStore = !GameTemplate.names.contains(template);
    if (fromStore && PackageNames.idProblem(template) != null) {
      throw UsageFailure('"$template" is not a template id.');
    }
    final local = argResults!.option('local');
    final checkouts = local == null
        ? const <Checkout>[]
        : DevLinks.scan(
            Directory(
              File(local).isAbsolute
                  ? local
                  : '${context.workingDirectory}/$local',
            ),
          );
    if (local != null && checkouts.isEmpty) {
      throw CommandFailure('No just_* packages in $local.');
    }
    final sdk =
        SdkLocator.locate(project.root, environment: context.environment) ??
        (throw const CommandFailure(
          'Flutter was not found. Install it, put it on the PATH, or set '
          'FLUTTER_ROOT.',
        ));
    final flutter = Version.tryParse(sdk.flutterVersion ?? '');
    final floor = VersionConstraint.tryParse(set.flutter);
    if (flutter != null && floor != null && !floor.allows(flutter)) {
      output.warn(
        'Flutter $flutter is older than the engine needs (${set.flutter}): '
        'run `flutter upgrade`.',
      );
    }
    final linked = local != null;
    final quiet = output.json;
    final direct = GameTemplate.direct(set, tools);

    final files = GameTemplate.render(
      fromStore ? GameTemplate.empty : template,
      names: names,
      set: set,
      tools: tools,
      org: argResults!.option('org')!,
      dependencies: [
        for (final p in direct.where((p) => !p.dev))
          ...TemplateRenderer.dependencyLines(p, hosted: linked),
      ],
      devDependencies: [
        for (final p in direct.where((p) => p.dev))
          if (linked || p.source != PackageSource.plugin)
            ...TemplateRenderer.dependencyLines(p, hosted: linked),
      ],
    );
    output.info(
      'Adding the ${fromStore || template == GameTemplate.empty ? 'game' : template} '
      'template…',
    );
    // flutter create's sample test names its own app class.
    final sample = project.file('test/widget_test.dart');
    if (sample.existsSync()) sample.deleteSync();
    files.forEach((path, text) => writeTextAtomic(project.file(path), text));
    final gitignore = project.file('.gitignore');
    writeTextAtomic(
      gitignore,
      GitIgnores.withDefaults(
        GameTemplate.withEditorIgnores(
          gitignore.existsSync() ? gitignore.readAsStringSync() : '',
        ),
      ),
    );
    final entitlements = project.file(GameTemplate.debugEntitlements);
    if (entitlements.existsSync()) {
      writeTextAtomic(
        entitlements,
        GameTemplate.withNetworkClient(entitlements.readAsStringSync()),
      );
    }

    output.info('Getting packages…');
    await _must(
      'flutter pub get',
      context.launcher.run(
        sdk.flutter,
        ['pub', 'get'],
        workingDirectory: project.root,
        toStderr: quiet,
      ),
    );

    // The store, as any plugin: trusted, or allowed (asked in a terminal).
    Future<int> store(List<String> args) => runTrustedPlugin(
      this,
      'just_asset_store',
      args,
      project: project,
      toStderr: quiet,
    );
    if (linked) {
      final items = [
        for (final c in checkouts)
          if (set[c.name]?.dev == true &&
              File('${c.path}/just_store.json').existsSync())
            c.path,
      ];
      if (items.isNotEmpty) {
        output.info('Registering the editor…');
        await _must('just store link', store(['store', 'link', ...items]));
      }
    } else {
      for (final p in direct) {
        if (p.source != PackageSource.plugin) continue;
        output.info('Installing ${p.name}…');
        await _must(
          'just store install ${p.name}',
          store(['store', 'install', p.name, '--yes']),
        );
      }
    }
    if (fromStore) {
      output.info('Laying the $template template over it…');
      await _must(
        'just store template $template',
        store([
          'store',
          'template',
          template,
          '--overwrite',
          '--yes',
          for (final s in argResults!.multiOption('source')) ...['--source', s],
        ]),
      );
    }
    final gpu = switchOnFlutterGpu(project);
    if (gpu > 0) {
      output.info('Switched Flutter GPU on in $gpu runner files (3D).');
    }
    output
      ..result = {
        'title': names.title,
        'template': template,
        'set': set.id,
        'linked': [for (final c in checkouts) c.name],
        'flutterGpu': gpu > 0,
      }
      ..line(
        'The game runs with `${context.invokedAs} game run`, and with its '
        'editor with `${context.invokedAs} game run --editor`.',
      );
    return 0;
  }

  /// Switches Flutter GPU on in [project]'s runners when the game draws in
  /// 3D (its code gives the engine a `Graphics3D`), and returns how many
  /// runner files changed.
  static int switchOnFlutterGpu(JustProject project) {
    final lib = Directory(project.path('lib'));
    final sources = !lib.existsSync()
        ? const <String>[]
        : [
            for (final f in lib.listSync(recursive: true).whereType<File>())
              if (f.path.endsWith('.dart')) f.readAsStringSync(),
          ];
    if (!GameTemplate.usesFlutterGpu(sources)) return 0;
    var changed = 0;
    GameTemplate.flutterGpuRunners.forEach((path, patch) {
      final file = project.file(path);
      if (!file.existsSync()) return;
      final text = file.readAsStringSync();
      final patched = patch(text);
      if (patched == text) return;
      writeTextAtomic(file, patched);
      changed++;
    });
    return changed;
  }

  static Future<void> _must(String what, Future<int> run) async {
    final code = await run;
    if (code != 0) throw CommandFailure('$what failed (exit code $code).');
  }
}
