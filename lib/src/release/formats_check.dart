/// Checking the project's saved files against the formats this version
/// reads.
library;

import 'dart:convert';

import 'package:just_game_engine_formats/just_game_engine_formats.dart';

/// One file's format, as checked.
final class FormatFinding {
  /// [path] (relative to the project) holds [kind] at [version], against
  /// [current]; [error] when it can't be read.
  const FormatFinding(
    this.path,
    this.kind,
    this.version,
    this.current, {
    this.error,
  });

  /// The file, relative to the project.
  final String path;

  /// What sort of file: `scene`, `timeline`, `animator graph`.
  final String kind;

  /// The version it declares.
  final int version;

  /// The newest version this one reads and writes.
  final int current;

  /// Why it can't be read, when it can't.
  final String? error;

  /// Saved by a newer engine than this one: it won't load.
  bool get tooNew => version > current;

  /// Saved in an older format: it loads (migrated in memory), and
  /// `just game migrate` rewrites it — when [kind] is one it can migrate
  /// ([FormatsCheck.migratable]).
  bool get old => version < current;

  /// This finding for `--json`.
  Map<String, Object?> toJson() => {
    'path': path,
    'kind': kind,
    'version': version,
    'current': current,
    'error': ?error,
  };
}

/// The versioned files under `assets/`: scenes, timelines, animator graphs,
/// the tag library and the physics layers. `JustProject.checkFormats()`
/// (the `GameProject` extension, where `dart:io` is) checks every one in a
/// project on disk.
abstract final class FormatsCheck {
  /// The kinds `just game migrate` rewrites in the current format: those
  /// with a migration (scenes, timelines) or a writer that brings them up to
  /// date (animator graphs). The others load as they are.
  static const Set<String> migratable = {'scene', 'timeline', 'animator graph'};

  /// [text], a file of [kind] ([migratable]), in the current format, written
  /// as the editor writes it, ending in a newline when [text] did. Throws
  /// [ArgumentError] for a kind it can't migrate, and what the formats throw
  /// for a file they can't read.
  static String migrated(String kind, String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Not a JSON object.');
    }
    const pretty = JsonEncoder.withIndent('  ');
    final out = switch (kind) {
      'scene' => pretty.convert(SceneFormat.migrate(json)),
      'timeline' => pretty.convert(TimelineFormat.migrate(json)),
      'animator graph' => AnimatorGraph.fromJson(json).encode(),
      _ => throw ArgumentError.value(kind, 'kind', 'Not a kind it migrates'),
    };
    // Keep the file's own ending: a final newline if it had one.
    return text.endsWith('\n') && !out.endsWith('\n') ? '$out\n' : out;
  }

  /// The kind of versioned file at [path] (relative to the project, with
  /// `/` between parts) — `scene`, `timeline`, `animator graph`,
  /// `tag library` or `physics layers` — or null for any other file.
  static String? kindOf(String path) => _formatOf(path)?.$1;

  static (String, int, int Function(Map<String, dynamic>))? _formatOf(
    String path,
  ) => switch (path) {
    _ when path.endsWith('.scene.json') => (
      'scene',
      SceneFormat.current,
      SceneFormat.versionOf,
    ),
    _ when path.endsWith('.timeline.json') => (
      'timeline',
      TimelineFormat.current,
      TimelineFormat.versionOf,
    ),
    _ when path.endsWith('.animator.json') => (
      'animator graph',
      AnimatorGraph.formatVersion,
      AnimatorGraph.versionOf,
    ),
    TagsFile.path => (
      'tag library',
      TagsFile.formatVersion,
      TagsFile.versionOf,
    ),
    PhysicsLayersFile.path => (
      'physics layers',
      PhysicsLayersFile.formatVersion,
      PhysicsLayersFile.versionOf,
    ),
    _ => null,
  };

  /// The file at [path] (relative to the project, [kindOf]), whose text is
  /// [text], checked against the formats this version reads; null when it
  /// is not a versioned file. A file that can't be read as its kind is a
  /// finding with an [FormatFinding.error], never a throw.
  static FormatFinding? check(String path, String text) {
    final format = _formatOf(path);
    if (format == null) return null;
    final (kind, current, versionOf) = format;
    try {
      final json = jsonDecode(text);
      if (kind == 'tag library' && json is List) {
        final problems = TagsFile.problems(json);
        return FormatFinding(
          path,
          kind,
          1,
          current,
          error: problems.isEmpty ? null : problems.join(' '),
        );
      }
      if (json is! Map<String, dynamic>) {
        return FormatFinding(
          path,
          kind,
          0,
          current,
          error: 'not a JSON object',
        );
      }
      var problems = switch (kind) {
        'tag library' => TagsFile.problems(json),
        'physics layers' => PhysicsLayersFile.problems(json),
        _ => const <String>[],
      };
      final version = versionOf(json);
      var newest = current;
      if (kind == 'animator graph' && version <= current) {
        // A graph is written as version 1 unless it uses a version 2
        // feature, so version 1 is as current as it gets for most.
        final graph = AnimatorGraph.fromJson(json);
        newest = graph.usesVersion2 ? 2 : 1;
        problems = graph.validate();
      }
      return FormatFinding(
        path,
        kind,
        version,
        newest,
        error: problems.isEmpty ? null : problems.join(' '),
      );
    } on FormatException catch (e) {
      return FormatFinding(path, kind, 0, current, error: e.message);
    }
  }

  /// The versioned file at [path] that could not be read at all — [why] —
  /// as a finding; null when [path] is not a versioned file.
  static FormatFinding? unreadable(String path, String why) {
    final format = _formatOf(path);
    if (format == null) return null;
    final (kind, current, _) = format;
    return FormatFinding(path, kind, 0, current, error: 'unreadable: $why');
  }
}
