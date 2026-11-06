/// Proving from the source that the editor can't reach a release build.
library;

import 'release_rules.dart';

/// What a Dart file imports, for the walk that proves no editor code is
/// reachable from a game's entry point: every `import`, `export` and
/// `part`, conditional imports' every branch too. A path that reaches a
/// [ReleaseRules.forbidden] library, or the project's own `lib/editor/`,
/// would ship the editor.
///
/// `JustProject.editorReachableFrom` (the `ProjectGame` extension, where
/// `dart:io` is) walks a project on disk with it. A check of the compiled
/// build (`JustProject.checkReleaseBuild`, `ReleaseBuild`) is the ground
/// truth; the walk is the fast one, for tests and before a build.
abstract final class ReleaseImports {
  static final RegExp _directive = RegExp(
    r'''^\s*(?:import|export|part)\s+(?:of\s+)?['"]([^'"]+)['"]|if\s*\([^)]*\)\s*['"]([^'"]+)['"]''',
    multiLine: true,
  );

  static final RegExp _scheme = RegExp(r'^([a-zA-Z][\w+.-]*):');

  /// The Dart files [source] imports, exports or names as a part (or as
  /// the library it is part of), as written: `package:` URIs and relative
  /// paths, conditional imports' every branch included, in order. `dart:`
  /// libraries and other schemes are left out.
  static List<String> dartUrisIn(String source) => [
    for (final m in _directive.allMatches(source))
      if (m.group(1) ?? m.group(2) case final String uri
          // Only Dart files: the conditional-import pattern also matches a
          // collection `if (...) 'text'`, which is no import at all.
          when uri.endsWith('.dart') &&
              switch (_scheme.firstMatch(uri)?.group(1)) {
                null || 'package' => true,
                _ => false,
              })
        uri,
  ];
}

/// The import walk could not look everywhere it had to, so it proves
/// nothing: the entry point is not there, the project's packages were never
/// fetched, or an import names a package pub did not resolve or a file that
/// is not there.
///
/// `JustProject.editorReachableFrom` throws it rather than say no editor
/// code is reachable without having looked; `just game check` and
/// `just game build` fail with its [message].
final class ReleaseImportsUnchecked implements Exception {
  /// The walk from [entry] could not look where [reasons] say; it found
  /// [reachable] on the way.
  const ReleaseImportsUnchecked(
    this.entry,
    this.reasons, {
    this.reachable = const [],
  });

  /// The entry point the walk started from, relative to the project.
  final String entry;

  /// Where it could not look, and why: one sentence each.
  final List<String> reasons;

  /// The editor code it found anyway, as `entry -> uri -> uri` trails.
  final List<String> reachable;

  /// What went unchecked, in sentences.
  String get message =>
      'The editor-import check of $entry proves nothing: ${reasons.join(' ')}';

  @override
  String toString() => 'ReleaseImportsUnchecked: $message';
}
