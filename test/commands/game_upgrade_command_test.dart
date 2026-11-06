// `just game upgrade`, the hook `just upgrade` runs: the engine's
// packages moved, one line each, no pub get.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:test/test.dart';

import '../support/fake_launcher.dart';

void main() {
  // The set's constraints: what an upgrade moves each to.
  String set(String name) => GameSet.current[name]!.constraint;
  final engine = set('just_game_engine');
  final editor = set('just_game_engine_editor');

  late Directory tmp;
  late GameHarness h;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('just_hooks_');
    h = GameHarness('${tmp.path}/game')..write('pubspec.yaml', 'name: game\n');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('game upgrade', () {
    // just_tiled is on the set already: it stays.
    final pubspec =
        'name: game\r\n'
        'dependencies:\r\n'
        '  just_game_engine: ^1.6.0 # the engine\r\n'
        '  just_tiled: ${set('just_tiled')}\r\n'
        'dev_dependencies:\r\n'
        '  just_asset_store:\r\n'
        '    git:\r\n'
        '      url: https://example.com/store\r\n'
        '  just_game_engine_editor: ^0.0.1\r\n';

    setUp(() => h.write('pubspec.yaml', pubspec));

    test('--check says what would move, and changes nothing', () async {
      expect(
        await h.just(['game', 'upgrade', '--check', '--json']),
        0,
        reason: '${h.err}',
      );
      final result = (jsonDecode('${h.out}') as Map)['result'] as Map;
      expect(result['packages'], {
        'just_game_engine': {'from': '^1.6.0', 'to': engine},
        'just_game_engine_editor': {'from': '^0.0.1', 'to': editor},
      });
      expect(result['changed'], isFalse);
      expect(h.read('pubspec.yaml'), pubspec);
    });

    test('moves one line each, never runs pub get, and asks first', () async {
      expect(await h.just(['game', 'upgrade']), 1);
      expect('${h.err}', contains('needs a yes'));
      expect(h.read('pubspec.yaml'), pubspec);

      expect(await h.just(['game', 'upgrade', '--yes']), 0, reason: '${h.err}');
      final next = h.read('pubspec.yaml')!;
      expect(next, contains('  just_game_engine: $engine # the engine\r\n'));
      expect(
        next,
        contains('  just_tiled: ${set('just_tiled')}\r\n'),
        reason: 'current',
      );
      expect(
        next,
        contains('      url: https://example.com/store\r\n'),
        reason: 'a block stays as it is',
      );
      expect(next, contains('  just_game_engine_editor: $editor\r\n'));
      expect(h.launcher.runs, isEmpty, reason: '`just upgrade` fetches');

      h.answer = 'n';
      h.write('pubspec.yaml', pubspec);
      expect(await h.just(['game', 'upgrade'], interactive: true), 1);
      expect('${h.err}', contains('the upgrade was declined'));
      expect(h.read('pubspec.yaml'), pubspec);

      h.out.clear();
      expect(await h.just(['game', 'upgrade', '--yes']), 0);
      expect(await h.just(['game', 'upgrade', '--yes']), 0);
      expect(
        '${h.out}',
        contains('needs moving to the ${GameSet.current.id} set'),
      );
    });
  });

  test('game upgrade never moves a package ahead of the set back', () async {
    const ahead =
        'name: game\n'
        'dependencies:\n'
        '  just_game_engine: ^3.0.0\n'
        '  just_physics_engine: ^2.1.0\n';
    h.write('pubspec.yaml', ahead);
    expect(await h.just(['game', 'upgrade', '--yes', '--json']), 0);
    final result = (jsonDecode('${h.out}') as Map)['result'] as Map;
    expect(result['packages'], isEmpty);
    expect(h.read('pubspec.yaml'), ahead);
  });
}
