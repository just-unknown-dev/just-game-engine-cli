/// When the tool may rewrite saved files in a newer format.
library;

import 'dart:convert';
import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_core_cli/project.dart';

/// Guards rewriting old files with the engine's rules alone.
///
/// A kit can have its own migration rules (the platformer kit does: its
/// components changed shape between formats), and today they run only
/// inside the engine, as a scene loads. Rewriting an old file without them
/// would mark it current while the kit's part was never brought up to date —
/// and nothing would migrate it again. So the tool refuses while a kit is
/// installed that hasn't given `just` its rules (a `migrate` hook in its
/// `just_plugin.json`), unless told the engine's rules are enough.
abstract final class MigrationSafety {
  /// The kits in [project] that have no `migrate` hook.
  static List<String> unsafeKits(JustProject project) {
    final config = PackageConfig.read(project.root);
    if (config == null) return const [];
    final hooked = {
      for (final p in PluginFinder.inProject(project))
        if (p.manifest.hooks.containsKey('migrate')) p.package,
    };
    final out = <String>[];
    for (final p in config.packages.values) {
      final manifest = File('${p.rootPath}/just_store.json');
      if (!manifest.existsSync() || hooked.contains(p.name)) continue;
      try {
        final json = jsonDecode(manifest.readAsStringSync());
        if (json is Map && json['kind'] == 'kit') out.add(p.name);
      } on FormatException {
        continue;
      }
    }
    return out..sort();
  }

  /// Throws [CommandFailure] when [project] has [unsafeKits] and
  /// [engineOnly] wasn't asked for. [retry] is the command that goes ahead
  /// anyway, for the message (`just game migrate --engine-only`).
  static void check(
    JustProject project, {
    required bool engineOnly,
    required String retry,
  }) {
    if (engineOnly) return;
    final kits = unsafeKits(project);
    if (kits.isEmpty) return;
    throw CommandFailure(
      'Nothing was rewritten: ${kits.join(', ')} may migrate its own '
      'components, and its rules run only in the engine. Open the scenes in '
      "the editor and save them (it migrates them with every package's "
      'rules as it loads them), or, if the kit has no rules for these '
      'formats, run `$retry`.',
    );
  }
}
