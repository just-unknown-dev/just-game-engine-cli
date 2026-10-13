/// Whether the editor has the project open.
library;

import 'package:just_core_cli/just_core_cli.dart';

/// The editor's sign that it has a project open: a file it touches every
/// few seconds while it runs ([path]). The editor holds the scenes in
/// memory and would save over a change made under it, so commands that
/// write scenes wait until it is closed.
///
/// A heartbeat, not a pid: a hot restart or a crash leaves the file behind,
/// and it goes stale on its own. `JustProject.editorIsOpen` (the
/// `GameProject` extension, where `dart:io` is) reads it from disk.
abstract final class EditorPresence {
  /// The file, relative to the project.
  static const String path = '${ProjectPaths.workDir}/editor.lock';

  /// How often the editor touches it.
  static const Duration beat = Duration(seconds: 5);

  /// How long after the last touch the editor counts as gone.
  static const Duration stale = Duration(seconds: 30);

  /// Whether a file last touched at [touched] says the editor is open, as
  /// of [now]: it was touched less than [stale] ago.
  static bool isFresh(DateTime touched, {DateTime? now}) =>
      (now ?? DateTime.now()).difference(touched) < stale;
}
