// The release checks name real things. Every class name and string
// `ReleaseRules` looks for in a build, every package and library it
// forbids, and every editor library the tests forbid, is still in the
// package it comes from: a rename there would blind the check, and a build
// holding the renamed code would pass.
//
// The names come from the monorepo's packages beside this one
// (`packages/`, `plugins/`); in a clone of this repository alone, where
// they aren't, the tests are skipped.

@TestOn('vm')
library;

import 'dart:io';

import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:test/test.dart';

import '../support/editor_libraries.dart';

/// [name]'s folder in the monorepo, or null when it isn't beside this
/// package.
Directory? _package(String name) {
  for (final at in ['../$name', '../../plugins/$name']) {
    final dir = Directory(at);
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
  }
  return null;
}

/// Every Dart source under the `lib/` of [names], joined; null when one of
/// them isn't beside this package.
String? _sources(List<String> names) {
  final out = StringBuffer();
  for (final name in names) {
    final dir = _package(name);
    if (dir == null) return null;
    for (final f in Directory('${dir.path}/lib').listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) {
        out.writeln(f.readAsStringSync());
      }
    }
  }
  return '$out';
}

/// Whether [source] declares a class (or mixin, enum…) called [name].
bool _declares(String source, String name) =>
    RegExp(r'\b(class|mixin|enum)\s+' + name + r'\b').hasMatch(source);

/// Whether a string literal in [source] holds [text] from its start.
bool _literal(String source, String text) =>
    source.contains("'$text") || source.contains('"$text');

/// The editor's packages: what the editor names come from.
const _editor = [
  'just_game_engine_editor',
  'just_editor_core',
  'just_sprite_editor',
  'just_input_editor',
];

/// Where 3-D physics lives: the engine's system, and the physics engine's
/// Jolt backend.
const _physics3D = ['just_game_engine', 'just_physics_engine'];

void main() {
  group("the editor's names", () {
    final sources = _sources(_editor);
    final skip = sources == null ? 'not in the monorepo' : null;

    test('each class name is declared there', () {
      expect([
        for (final name in ReleaseRules.coreClassNames)
          if (!_declares(sources!, name)) name,
      ], isEmpty);
    }, skip: skip);

    test('each string is a literal there', () {
      expect([
        for (final text in ReleaseRules.coreStrings)
          if (!_literal(sources!, text)) text,
      ], isEmpty);
    }, skip: skip);
  });

  group("3-D physics' names", () {
    final sources = _sources(_physics3D);
    final skip = sources == null ? 'not in the monorepo' : null;

    test('each class name is declared there', () {
      expect([
        for (final name in ReleaseRules.physics3DClassNames)
          if (!_declares(sources!, name)) name,
      ], isEmpty);
    }, skip: skip);

    test('each string is a literal there', () {
      expect([
        for (final text in ReleaseRules.physics3DStrings)
          if (!_literal(sources!, text)) text,
      ], isEmpty);
    }, skip: skip);
  });

  test('each package and library it forbids is there', () {
    final missing = <String>[];
    for (final entry in ReleaseRules.coreForbidden) {
      final slash = entry.indexOf('/');
      final name = slash < 0 ? entry : entry.substring(0, slash);
      final dir = _package(name);
      if (dir == null) {
        markTestSkipped('$name is not in the monorepo');
        return;
      }
      final library = slash < 0 ? '' : entry.substring(slash + 1);
      if (library.isNotEmpty &&
          !File('${dir.path}/lib/$library').existsSync()) {
        missing.add(entry);
      }
    }
    expect(missing, isEmpty);
  });

  test("the editor libraries the tests forbid are the editor's own", () {
    final missing = <String>[];
    for (final uri in editorLibraries) {
      final rest = uri.substring('package:'.length);
      final slash = rest.indexOf('/');
      final dir = _package(rest.substring(0, slash));
      if (dir == null) {
        markTestSkipped('${rest.substring(0, slash)} is not in the monorepo');
        return;
      }
      if (!File('${dir.path}/lib/${rest.substring(slash + 1)}').existsSync()) {
        missing.add(uri);
      }
    }
    expect(missing, isEmpty);
  });

  test('the guard itself sees a name that is gone', () {
    // If this passed for a name nobody declares, the tests above would
    // pass for the wrong reason.
    expect(
      _declares('class Physics3DSystem extends System {}', 'JoltWorld'),
      isFalse,
    );
    expect(
      _declares('final class JoltWorld implements X {}', 'JoltWorld'),
      isTrue,
    );
    expect(_literal("id: 'asset_store.open',", 'asset_store.open'), isTrue);
    expect(_literal('// asset_store.open', 'asset_store.open'), isFalse);
  });
}
