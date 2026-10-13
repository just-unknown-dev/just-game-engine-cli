// Switching Flutter GPU on in a new 3D game's runners, on the files
// `flutter create` 3.47.6 makes (test/fixtures/runners/): the switch goes
// where the platform reads it, once however often it is run, and each file
// keeps its line endings.

@TestOn('vm')
library;

import 'dart:io';

import 'package:just_game_engine_cli/just_game_engine_cli.dart';
import 'package:test/test.dart';

String _fixture(String name) =>
    File('test/fixtures/runners/$name').readAsStringSync();

int _crlf(String text) => '\r\n'.allMatches(text).length;

void main() {
  test(
    'a project uses Flutter GPU when its code gives the engine a Graphics3D',
    () {
      expect(
        GameTemplate.usesFlutterGpu(['EngineConfig(graphics3D: Graphics3D())']),
        isTrue,
      );
      expect(
        GameTemplate.usesFlutterGpu([
          'a',
          'graphics3D: Graphics3D(device: device),',
        ]),
        isTrue,
      );
      expect(
        GameTemplate.usesFlutterGpu(['EngineConfig(physics3D: Physics3D())']),
        isFalse,
      );
      expect(
        GameTemplate.usesFlutterGpu(['Graphics3D? get graphics3D']),
        isFalse,
      );
      expect(GameTemplate.usesFlutterGpu(const []), isFalse);
    },
  );

  final cases = {
    'windows_main.cpp': (
      GameTemplate.withFlutterGpuWindows,
      ['project.set_enable_flutter_gpu(true);'],
    ),
    'linux_my_application.cc': (
      GameTemplate.withFlutterGpuLinux,
      ['fl_dart_project_set_enable_flutter_gpu(project, TRUE);'],
    ),
    'AndroidManifest.xml': (
      GameTemplate.withFlutterGpuAndroid,
      [
        'io.flutter.embedding.android.EnableFlutterGPU',
        'io.flutter.embedding.android.ImpellerBackend',
        'android:value="vulkan"',
      ],
    ),
    'ios_Info.plist': (
      GameTemplate.withFlutterGpuIos,
      ['<key>FLTEnableFlutterGPU</key>'],
    ),
    'macos_Info.plist': (
      GameTemplate.withFlutterGpuMacos,
      ['<key>FLTEnableImpeller</key>', '<key>FLTEnableFlutterGPU</key>'],
    ),
  };

  for (final MapEntry(key: name, value: (patch, needles)) in cases.entries) {
    test('$name: switched on once, its line endings kept', () {
      final text = _fixture(name);
      final once = patch(text);
      expect(once, isNot(text));
      for (final n in needles) {
        expect(once, contains(n), reason: name);
      }
      expect(patch(once), once, reason: 'running it again changes nothing');
      if (_crlf(text) > 0) {
        expect(
          once.replaceAll('\r\n', '').contains('\n'),
          isFalse,
          reason: 'no bare LF in a CRLF file',
        );
      }
    });
  }

  test(
    'the Windows switch comes after the entry point arguments, before the window',
    () {
      final once = GameTemplate.withFlutterGpuWindows(
        _fixture('windows_main.cpp'),
      );
      final args = once.indexOf('project.set_dart_entrypoint_arguments(');
      final gpu = once.indexOf('project.set_enable_flutter_gpu(true);');
      final window = once.indexOf('FlutterWindow window(project);');
      expect(args, greaterThan(0));
      expect(gpu, greaterThan(args));
      expect(gpu, lessThan(window));
    },
  );

  test('the Linux switch comes after the whole two-line arguments call', () {
    final once = GameTemplate.withFlutterGpuLinux(
      _fixture('linux_my_application.cc'),
    );
    final args = once.indexOf('fl_dart_project_set_dart_entrypoint_arguments(');
    final gpu = once.indexOf('fl_dart_project_set_enable_flutter_gpu');
    final close = once.indexOf(');', args);
    expect(gpu, greaterThan(close));
    expect(once.indexOf('fl_view_new(project)'), greaterThan(gpu));
  });

  test(
    'Android meta-data sit inside the application; plist keys inside the dict',
    () {
      final manifest = GameTemplate.withFlutterGpuAndroid(
        _fixture('AndroidManifest.xml'),
      );
      expect(
        manifest.indexOf('EnableFlutterGPU'),
        lessThan(manifest.lastIndexOf('</application>')),
      );
      expect(
        manifest.indexOf('EnableFlutterGPU'),
        greaterThan(manifest.indexOf('<application')),
      );
      final plist = GameTemplate.withFlutterGpuMacos(
        _fixture('macos_Info.plist'),
      );
      expect(
        plist.indexOf('FLTEnableFlutterGPU'),
        lessThan(plist.lastIndexOf('</dict>')),
      );
    },
  );

  test('every runner in flutterGpuRunners has a fixture', () {
    expect(GameTemplate.flutterGpuRunners.keys, [
      'windows/runner/main.cpp',
      'linux/runner/my_application.cc',
      'android/app/src/main/AndroidManifest.xml',
      'ios/Runner/Info.plist',
      'macos/Runner/Info.plist',
    ]);
  });
}
