/// What `just game run`, `build` and `check` share: the Flutter they run,
/// and this machine's desktop.
library;

import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_core_cli/project.dart';
import 'package:meta/meta.dart';

/// This machine's desktop, as `flutter` names the platform: `windows`,
/// `macos` or `linux`.
@internal
String desktopPlatform() => Platform.isWindows
    ? 'windows'
    : Platform.isMacOS
    ? 'macos'
    : 'linux';

/// The Flutter SDK [command] runs for [project]: the one on the `PATH` or
/// `FLUTTER_ROOT`. Throws [CommandFailure] when there is none.
@internal
FlutterSdk flutterFor(JustCommand command, JustProject project) =>
    SdkLocator.locate(project.root, environment: command.context.environment) ??
    (throw const CommandFailure(
      'Flutter was not found. Install it, put it on the PATH, or set '
      'FLUTTER_ROOT.',
    ));
