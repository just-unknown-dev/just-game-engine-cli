/// `just game link`: the game's `link` hook.
library;

import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_core_cli/project.dart';

import '../create/game_set.dart';

/// `just game link [--unlink] [--check] <name>=<path>…`: what a game does
/// with local checkouts — the `link` hook `just dev link|unlink` runs, so
/// hidden from the help.
///
/// - After `just dev link`: the Asset Store items among the checkouts that
///   the pubspec lists (each with a `just_store.json`) are registered as
///   linked, with `just store link`. A store that may not run is a warning.
/// - Before `just dev unlink` (`--unlink --check`): refused while
///   `pubspec.yaml` asks pub.dev, by version, for one of them that the
///   [GameSet] gets only from git or the Asset Store — without the link pub
///   could not resolve the project.
/// - After `just dev unlink` (`--unlink`): a reminder that the store still
///   lists its items as linked.
final class GameLinkCommand extends JustCommand {
  /// The command and its options.
  GameLinkCommand() {
    argParser
      ..addFlag(
        'unlink',
        negatable: false,
        help: 'The links are going (with --check) or gone.',
      )
      ..addFlag(
        'check',
        negatable: false,
        help: 'Change nothing: fail, saying why, when the change would break.',
      );
  }

  @override
  String get name => 'link';

  @override
  String get description =>
      'Register linked checkouts with the Asset Store, and keep links only '
      'they can supply (what `just dev link|unlink` runs).';

  @override
  String get invocation =>
      '${context.invokedAs} game link [--unlink] [--check] <name>=<path>...';

  @override
  bool get hidden => true;

  @override
  Future<int> run() async {
    final project = requireProject();
    final links = <String, String>{};
    for (final a in rest) {
      final at = a.indexOf('=');
      if (at <= 0 || at == a.length - 1) {
        throw UsageFailure('"$a" is not <name>=<path>.');
      }
      links[a.substring(0, at)] = a.substring(at + 1);
    }
    final pubspec = project.readText(JustProject.pubspec) ?? '';
    final unlink = argResults!.flag('unlink');
    final check = argResults!.flag('check');

    if (unlink && check) {
      final stranded = GameSet.current.linkOnly(pubspec, links.keys);
      output.result = {'stranded': stranded};
      if (stranded.isNotEmpty) {
        throw CommandFailure(
          'Nothing was unlinked: pubspec.yaml asks pub.dev for '
          '${stranded.join(', ')} by version, but they come only from git or '
          'the Asset Store, so without the links pub could not resolve the '
          'project. Give each its real source in pubspec.yaml first — '
          'just_asset_store as a git dependency (`git: url: '
          '${GameSet.current['just_asset_store']?.git}`), a store item '
          'removed from pubspec.yaml and installed with '
          '`${context.invokedAs} store install <id>` — or keep the links.',
        );
      }
      return 0;
    }
    if (unlink) {
      if (project.file('just_store.lock.json').existsSync()) {
        output.line(
          'Store items listed as linked stay listed: '
          '`${context.invokedAs} store unlink <id>` forgets one.',
        );
      }
      return 0;
    }
    final items = [
      for (final e in links.entries)
        if (File('${e.value}/just_store.json').existsSync() &&
            RegExp(
              '^\\s+${RegExp.escape(e.key)}\\s*:',
              multiLine: true,
            ).hasMatch(pubspec))
          e.value,
    ];
    output.result = {'registered': <String>[]};
    if (check || items.isEmpty) return 0;
    final hasStore = PluginFinder.inProject(
      project,
    ).any((p) => p.package == 'just_asset_store');
    if (!hasStore) {
      output.info(
        'The project has no just_asset_store: the store items among the '
        'links are not registered.',
      );
      return 0;
    }
    final int code;
    try {
      code = await runTrustedPlugin(
        this,
        'just_asset_store',
        ['store', 'link', ...items],
        project: project,
        toStderr: output.json,
      );
    } on CommandFailure catch (e) {
      output.warn(
        'The store items were not registered as linked: ${e.message} Then '
        'run `${context.invokedAs} store link <folder>`.',
      );
      return 0;
    }
    if (code != 0) {
      throw CommandFailure('just store link failed (exit code $code).');
    }
    output.result = {'registered': items};
    return 0;
  }
}
