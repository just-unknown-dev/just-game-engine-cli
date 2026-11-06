/// `just game mcp`: the engine's docs and API, at the versions this game
/// uses, for an AI assistant.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:just_core_cli/just_core_cli.dart';
import 'package:meta/meta.dart';

import '../mcp/mcp.dart';
import '../project/project.dart';

/// `just game mcp`: an MCP server on stdin and stdout for the game — the
/// guides, notes and API of the engine packages it resolved, and its
/// scene and setup checks. An AI assistant starts it (`.mcp.json`,
/// `.vscode/mcp.json`); it runs until the assistant closes it.
@internal
final class GameMcpCommand extends JustCommand {
  /// The command; [game] makes the `just game` command its tools run
  /// in-process (`GameCommand.new`), a fresh one for each run.
  GameMcpCommand(this.game);

  /// Makes the `just game` command the tools run.
  final JustCommand Function() game;

  @override
  String get name => 'mcp';

  @override
  String get description =>
      "Serve the engine's guides and API — at the versions this game uses — "
      'and its scene and setup checks to an AI assistant over MCP (stdio). '
      'The assistant starts it; see the game\'s .mcp.json.';

  // Its stdout is the MCP stream: no document of the runner's.
  @override
  bool get printsOwnDocument => true;

  @override
  Future<int> run() async {
    final project = requireProject();
    if (context.interactive) {
      context.err.writeln(
        'just game mcp talks MCP on stdin and stdout: an AI assistant starts '
        'it. Waiting for one (Ctrl+C to stop).',
      );
    }
    final knowledge = GameKnowledge.read(project.root);
    final server = GameMcpServer(
      stdioChannel(input: stdin, output: stdout),
      knowledge: knowledge,
      runJust: (args) => _runInProcess(project, args),
      editorOpen: project.editorIsOpen,
      version: knowledge.packages['just_game_engine_cli']?.version ?? '',
    );
    await server.done;
    return 0;
  }

  /// Runs `just` [args] on [project] in this process, with `--json`, its
  /// output captured: stdout is the MCP stream.
  Future<InProcessRun> _runInProcess(
    JustProject project,
    List<String> args,
  ) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runJustPlugin(
      [...args, '--json', '--project', project.root],
      [game()],
      context: JustContext(
        workingDirectory: project.root,
        out: out,
        err: err,
        readLine: () => null,
        interactive: false,
        environment: context.environment,
        invokedAs: context.invokedAs,
        version: context.version,
        launcher: const _CapturedLauncher(),
      ),
    );
    Object? document;
    try {
      document = jsonDecode(out.toString());
    } on FormatException {
      document = null;
    }
    return (exitCode: code, document: document, messages: '$err');
  }
}

/// Starts programs with their output on stderr, never on this process's
/// stdout (the MCP stream).
final class _CapturedLauncher implements Launcher {
  const _CapturedLauncher();

  @override
  Future<int> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String> environment = const {},
    bool toStderr = false,
    StringSink? stdout,
    StringSink? collect,
  }) => const ProcessLauncher().run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    toStderr: stdout == null,
    stdout: stdout,
    collect: collect,
  );
}
