// `just game mcp`'s API, read from source.

@TestOn('vm')
library;

import 'dart:io';

import 'package:just_game_engine_cli/src/mcp/api_index.dart';
import 'package:test/test.dart';

import '../support/unreadable.dart';

void main() {
  group('the API from source', () {
    DartFileScan scan(String source) =>
        scanDartSource(source, package: 'p', file: 'lib/a.dart');

    ApiDeclaration only(DartFileScan s, String name) =>
        s.declarations.singleWhere((d) => d.name == name);

    test('a class: its doc, header, constructors and members', () {
      final s = scan(r'''
/// A body that moves.
///
/// More detail.
class Body extends Component with Movable implements Thing {
  /// Makes one.
  Body({this.speed = 1.0, Map<String, int> extra = const {}})
    : _x = {'a': 1}, assert(speed >= 0) {
    if (speed > 2) { print('${speed + {1: 2}.length} }'); }
  }

  Body.named(double s) : this(speed: s);

  factory Body.fromJson(Map<String, Object?> json) => Body(speed: (json['s'] as num?)?.toDouble() ?? 0);

  /// How fast.
  double speed;

  final Map<String, int> _x;

  /// The default.
  static const double defaultSpeed = 2.5;

  /// Whether it moves.
  bool get moving => speed > 0 && {1, 2}.isNotEmpty;

  set moving(bool value) {
    speed = value ? 1 : 0;
  }

  @override
  void update(double dt) {
    final s = '}';
  }

  @Deprecated('Use update instead.')
  void tick(double dt) => update(dt);

  bool operator ==(Object other) => other is Body;

  void operator []=(int i, double v) {}

  void Function(int)? onHit;

  void _hidden() {}
}

class _Private { void visible() {} }
''');
      final body = only(s, 'Body');
      expect(body.kind, 'class');
      expect(body.doc, startsWith('A body that moves.'));
      expect(body.summary, 'A body that moves.');
      expect(body.supertypes, ['Component', 'Movable', 'Thing']);
      expect(s.declarations.map((d) => d.name), ['Body']);
      final members = {for (final m in body.members) m.name: m};
      expect(members.keys, [
        'Body',
        'Body.named',
        'Body.fromJson',
        'speed',
        'defaultSpeed',
        'moving',
        'update',
        'tick',
        'operator ==',
        'operator []=',
        'onHit',
      ]);
      expect(
        members['Body']!.signature,
        'Body({this.speed = 1.0, Map<String, int> extra = const {}})',
      );
      expect(members['Body']!.doc, 'Makes one.');
      expect(members['Body.fromJson']!.kind, 'constructor');
      expect(members['speed']!.signature, 'double speed');
      expect(
        members['defaultSpeed']!.signature,
        'static const double defaultSpeed = 2.5',
      );
      expect(
        [
          for (final m in body.members)
            if (m.name == 'moving') '${m.kind}: ${m.signature}',
        ],
        ['getter: bool get moving', 'setter: set moving(bool value)'],
      );
      expect(members['update']!.isOverride, isTrue);
      expect(members['tick']!.deprecated, 'Use update instead.');
      expect(members['onHit']!.kind, 'field');
      expect(members['Body']!.line, 6);
    });

    test('enums, mixins, extensions, typedefs and top-level names', () {
      final s = scan(r'''
/// Which way.
enum Side {
  /// Left.
  left,
  @Deprecated('no') right('r'),
  up;

  const Side([this.code = '']);
  final String code;
  bool get vertical => this == up;
}

mixin Movable on Component { void move() {} }

extension BodyX on Body { double get half => speed / 2; }

typedef Hit = void Function(Body a, {int force});

/// Two.
const int two = 2;

Engine makeEngine({int fps = 60}) => Engine();

int _secret = 1;
''');
      final side = only(s, 'Side');
      expect(side.kind, 'enum');
      expect(side.values, ['left', 'right', 'up']);
      expect(side.members.map((m) => m.name), ['code', 'vertical']);
      expect(only(s, 'Movable').kind, 'mixin');
      expect(only(s, 'Movable').supertypes, ['Component']);
      expect(only(s, 'BodyX').kind, 'extension');
      expect(only(s, 'BodyX').members.single.name, 'half');
      expect(
        only(s, 'Hit').signature,
        'typedef Hit = void Function(Body a, {int force})',
      );
      expect(only(s, 'two').signature, 'const int two = 2');
      expect(only(s, 'makeEngine').kind, 'function');
      expect(s.declarations.any((d) => d.name == '_secret'), isFalse);
    });

    test('exports, parts and libraries across packages', () {
      final tmp = Directory.systemTemp.createTempSync('just_mcp_api_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      void write(String path, String text) => (File(
        '${tmp.path}/$path',
      )..createSync(recursive: true)).writeAsStringSync(text);
      write('just_game_engine/lib/just_game_engine.dart', '''
export 'src/world.dart' hide Internal;
export 'package:just_inputs/just_inputs.dart' show InputAction;
''');
      write('just_game_engine/lib/src/world.dart', '''
part 'world_part.dart';
/// The world.
class World {}
class Internal {}
class Hidden {}
''');
      write('just_game_engine/lib/src/world_part.dart', '''
part of 'world.dart';
class FromPart extends World {}
''');
      write('just_game_engine/lib/src/hidden.dart', 'class NotExported {}');
      write('just_inputs/lib/just_inputs.dart', "export 'src/a.dart';");
      write('just_inputs/lib/src/a.dart', '''
class InputAction {}
class InputMap {}
''');
      final api = ApiIndex.read({
        'just_game_engine': '${tmp.path}/just_game_engine',
        'just_inputs': '${tmp.path}/just_inputs',
      });
      final names = api.declarations.map((d) => d.name).toSet();
      expect(names, {'World', 'Hidden', 'FromPart', 'InputAction', 'InputMap'});
      expect(api.lookup('InputAction').single.libraries, [
        'package:just_game_engine/just_game_engine.dart',
        'package:just_inputs/just_inputs.dart',
      ]);
      expect(api.lookup('InputMap').single.libraries, [
        'package:just_inputs/just_inputs.dart',
      ]);
      expect(api.subtypesOf('World').map((d) => d.name), ['FromPart']);
      expect(api.lookup('world').single.doc, 'The world.');
      expect(api.similar('Wrold'), contains('World'));
    });

    test("a folder it can't list is left out, named; the rest is read", () {
      final tmp = Directory.systemTemp.createTempSync('just_api_');
      final secret = Directory('${tmp.path}/p/lib/secret')
        ..createSync(recursive: true);
      addTearDown(() {
        makeReadable(secret);
        tmp.deleteSync(recursive: true);
      });
      File('${secret.path}/a.dart').writeAsStringSync('class Secret {}');
      File('${tmp.path}/p/lib/p.dart').writeAsStringSync('class Kept {}');
      File('${tmp.path}/q/lib/q.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('class Other {}');
      if (!makeUnreadable(secret)) {
        markTestSkipped('this user can read any folder');
        return;
      }
      final api = ApiIndex.read({'p': '${tmp.path}/p', 'q': '${tmp.path}/q'});
      expect(api.lookup('Kept'), hasLength(1));
      expect(api.lookup('Other'), hasLength(1));
      expect(api.problems, [contains('p: ')]);
      expect(api.problems.single, contains('secret could not be listed'));
    });
  });
}
