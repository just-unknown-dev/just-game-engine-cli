// What the tests run commands with: a launcher that records what would
// have run, and a project in a temporary folder.

import 'dart:convert';
import 'dart:io';

import 'package:just_core_cli/just_core_cli.dart';
import 'package:just_core_cli/project.dart';
import 'package:just_game_engine_cli/just_game_engine_cli.dart';

/// One program run, as the launcher saw it.
final class Run {
  /// [arguments] run in [workingDirectory] with [env], printing to stderr
  /// when [toStderr].
  Run(this.arguments, this.workingDirectory, this.env, this.toStderr);

  /// The arguments.
  final List<String> arguments;

  /// Where it ran.
  final String? workingDirectory;

  /// The environment it was given.
  final Map<String, String> env;

  /// Whether its output went to stderr.
  final bool toStderr;

  @override
  String toString() => arguments.join(' ');
}

/// A launcher that records each run and, for `pub get`, resolves
/// [packages] (each package's folder, from a local checkout).
final class FakeLauncher implements Launcher {
  /// A launcher whose `pub get` resolves [packages] ([servers] as in
  /// [resolve]).
  FakeLauncher({this.packages = const [], this.servers = const {}});

  /// What `pub get` resolves.
  List<Directory> packages;

  /// The packages `pub get` says came from a package server, by name.
  Map<String, String> servers;

  /// Every run so far.
  final List<Run> runs = [];

  /// The exit code of each run; 0 when null.
  int Function(List<String> arguments)? exitCodeFor;

  @override
  Future<int> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String> environment = const {},
    bool toStderr = false,
    StringSink? stdout,
  }) async {
    runs.add(Run(arguments, workingDirectory, environment, toStderr));
    final code = exitCodeFor?.call(arguments) ?? 0;
    if (code == 0 &&
        arguments.length >= 2 &&
        arguments[0] == 'pub' &&
        arguments[1] == 'get' &&
        workingDirectory != null) {
      resolve(Directory(workingDirectory), packages, servers: servers);
    }
    return code;
  }
}

/// [dir]'s package_config and pubspec.lock, resolving [packages] from
/// local checkouts (path dependencies) — or, for those [servers] names,
/// from that package server.
void resolve(
  Directory dir,
  List<Directory> packages, {
  Map<String, String> servers = const {},
}) {
  String nameOf(Directory d) =>
      d.uri.pathSegments.where((s) => s.isNotEmpty).last;
  File('${dir.path}/.dart_tool/package_config.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          for (final p in packages)
            {
              'name': nameOf(p),
              'rootUri': p.absolute.uri.toString(),
              'packageUri': 'lib/',
            },
        ],
      }),
    );
  final lock = StringBuffer('packages:\n');
  for (final p in packages) {
    final server = servers[nameOf(p)];
    if (server != null) {
      lock
        ..writeln('  ${nameOf(p)}:')
        ..writeln('    dependency: "direct dev"')
        ..writeln('    description:')
        ..writeln('      name: ${nameOf(p)}')
        ..writeln('      url: "$server"')
        ..writeln('    source: hosted')
        ..writeln('    version: "0.1.0"');
      continue;
    }
    final path = normalPath(p.absolute.path).replaceAll(r'\', r'\\');
    lock
      ..writeln('  ${nameOf(p)}:')
      ..writeln('    dependency: "direct dev"')
      ..writeln('    description:')
      ..writeln('      path: "$path"')
      ..writeln('      relative: false')
      ..writeln('    source: path')
      ..writeln('    version: "0.1.0"');
  }
  File('${dir.path}/pubspec.lock').writeAsStringSync('$lock');
}

/// A package [name] in [parent], with a `just_plugin.json` of [manifest]
/// when given, and a `just_store.json` of [store] when given.
Directory package(
  Directory parent,
  String name, {
  Object? manifest,
  Object? store,
}) {
  final dir = Directory('${parent.path}/$name')..createSync(recursive: true);
  File(
    '${dir.path}/pubspec.yaml',
  ).writeAsStringSync('name: $name\nversion: 0.1.0\n');
  if (manifest != null) {
    File(
      '${dir.path}/just_plugin.json',
    ).writeAsStringSync(jsonEncode(manifest));
  }
  if (store != null) {
    File('${dir.path}/just_store.json').writeAsStringSync(jsonEncode(store));
  }
  return dir;
}

/// Runs `just game` commands on a project in a temporary folder, with the
/// output captured and a [FakeLauncher].
final class GameHarness {
  /// A harness for the project in [root].
  GameHarness(String root, {FakeLauncher? launcher})
    : project = JustProject(root),
      launcher = launcher ?? FakeLauncher();

  /// The project.
  JustProject project;

  /// What runs.
  final FakeLauncher launcher;

  /// What the commands printed for a person, and on stderr.
  final StringBuffer out = StringBuffer(), err = StringBuffer();

  /// Environment variables beyond the defaults.
  Map<String, String> env = {};

  /// Runs `just` + [args] (`game scene list`) through the plugin's
  /// entry point, as `just` would.
  Future<int> just(List<String> args, {bool interactive = false}) =>
      runJustPlugin(args, [
        GameCommand(),
      ], context: context(interactive: interactive));

  /// The context the commands run in.
  JustContext context({bool interactive = false}) => JustContext(
    workingDirectory: project.root,
    out: out,
    err: err,
    interactive: interactive,
    readLine: () => 'y',
    environment: {'PUB_CACHE': '${project.root}/../none', ...env},
    launcher: launcher,
  );

  /// The text of [path] in the project, or null.
  String? read(String path) => project.readText(path);

  /// Writes [text] to [path] in the project.
  void write(String path, String text) => project.file(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(text);
}
