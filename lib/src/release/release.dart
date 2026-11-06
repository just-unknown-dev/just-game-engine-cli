/// Proving the editor never ships, from text, on every platform (the web
/// included): what must not reach a release ([ReleaseRules]), the imports a
/// source names ([ReleaseImports]), the check of a release build's files
/// ([ReleaseBuild]), and the saved formats ([FormatsCheck]).
///
/// Nothing here reads a disk: no `dart:io`, no
/// `package:just_core_cli/project.dart`.
library;

export 'formats_check.dart';
export 'release_build.dart';
export 'release_imports.dart';
export 'release_rules.dart';
