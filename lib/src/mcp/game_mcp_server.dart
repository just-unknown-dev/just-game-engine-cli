/// `just game mcp`'s server: the guides, notes and API of the engine a game
/// resolved, and checks of its scenes and setup, as MCP tools an AI
/// assistant calls. Everything it does only reads.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dart_mcp/server.dart';

import 'dart_api.dart';
import 'game_knowledge.dart';
import 'text_search.dart';

/// What a `just` command run in-process gave: its exit code, its `--json`
/// document, and what it said on stderr.
typedef JustRun = ({int exitCode, Object? document, String messages});

/// Runs `just` [args] on the game in-process, with `--json`.
typedef JustRunner = Future<JustRun> Function(List<String> args);

/// The MCP server: tools for the game at [GameKnowledge.projectRoot].
base class GameMcpServer extends MCPServer with ToolsSupport {
  /// A server on [channel] for the game [knowledge] describes; [runJust]
  /// runs its `just game` commands, and [editorOpen] says whether the
  /// editor has it open. [version] is this tool's.
  GameMcpServer(
    super.channel, {
    required this.knowledge,
    required this.runJust,
    required bool Function() editorOpen,
    String version = '',
  }) : _editorOpen = editorOpen,
       super.fromStreamChannel(
         implementation: Implementation(
           name: 'just_game_engine',
           title: 'Just Game Engine',
           version: version,
         ),
         instructions: instructionsFor(knowledge),
       ) {
    registerTool(projectInfoTool, _projectInfo);
    registerTool(searchDocsTool, _searchDocs);
    registerTool(readDocTool, _readDoc);
    registerTool(getApiTool, _getApi);
    registerTool(listScenesTool, _listScenes);
    registerTool(validateScenesTool, _validateScenes);
    registerTool(checkGameTool, _checkGame);
  }

  /// The game's packages, guides and API.
  final GameKnowledge knowledge;

  /// Runs `just game …` on the game.
  final JustRunner runJust;

  final bool Function() _editorOpen;

  static final _readOnly = ToolAnnotations(
    readOnlyHint: true,
    openWorldHint: false,
  );

  /// `project_info`.
  static final projectInfoTool = Tool(
    name: 'project_info',
    title: 'Game and engine versions',
    description:
        'The game: its folder, the Just Game Engine packages it resolved and '
        'their versions (the docs and API the other tools serve are these '
        'versions), its scenes, and whether the level editor has it open.',
    inputSchema: Schema.object(),
    annotations: _readOnly,
  );

  /// `search_docs`.
  static final searchDocsTool = Tool(
    name: 'search_docs',
    title: 'Search the engine docs and API',
    description:
        "Keyword search over the engine's guides, its packages' notes "
        '(README, MIGRATION, CHANGELOG) and their public API, at the '
        'versions this game uses. Use it before writing engine code: the '
        'engine is new and its 2.x API differs from 1.x and from other '
        'Flutter engines. Each hit says how to read all of it: read_doc for '
        'a guide or note, get_api for a symbol.',
    inputSchema: Schema.object(
      properties: {
        'query': Schema.string(
          description:
              'Words or names: "one-way platform jump", "CharacterBody2DComponent", '
              '"load scene from json".',
        ),
        'kind': Schema.string(
          description:
              'Only guides, only notes, or only the API (default all).',
          enumValues: ['all', 'guide', 'notes', 'api'],
        ),
        'limit': Schema.int(
          description: 'How many hits (default 8, at most 25).',
          minimum: 1,
          maximum: 25,
        ),
      },
      required: ['query'],
    ),
    annotations: _readOnly,
  );

  /// `read_doc`.
  static final readDocTool = Tool(
    name: 'read_doc',
    title: 'Read a guide or package note',
    description:
        "Read one of the engine's guides by its slug (`ecs`, `physics-2d`, "
        '`scenes`, `migration`, …) or a package note such as '
        '`just_game_engine/MIGRATION.md`, whole or one `## ` section. With no '
        '`doc`, lists the guides and notes there are.',
    inputSchema: Schema.object(
      properties: {
        'doc': Schema.string(
          description:
              'A guide slug, or `package/FILE.md`. Leave out to list them.',
        ),
        'section': Schema.string(
          description: 'A `## ` heading of it (or its start): only that part.',
        ),
      },
    ),
    annotations: _readOnly,
  );

  /// `get_api`.
  static final getApiTool = Tool(
    name: 'get_api',
    title: 'Look up an API symbol',
    description:
        'The exact signature, doc comment and import of a public class, '
        'function or member of the engine packages this game uses: '
        '`CharacterBody2DComponent`, `Engine.subsystem`, `SystemPriorities`, '
        '`World.createEntityWithComponents`. A type comes with its '
        'constructors, members and subtypes; a name it does not know comes '
        'with the closest it does. Deprecated APIs say what replaces them.',
    inputSchema: Schema.object(
      properties: {
        'symbol': Schema.string(
          description: 'A type, `Type.member`, or a top-level name.',
        ),
        'package': Schema.string(
          description: 'Only this package (e.g. `just_game_engine`).',
        ),
      },
      required: ['symbol'],
    ),
    annotations: _readOnly,
  );

  /// `list_scenes`.
  static final listScenesTool = Tool(
    name: 'list_scenes',
    title: "List the game's scenes",
    description:
        "The game's levels (assets/scenes/*.scene.json) in play order "
        '(scenes.json), each with its mode (2d or 3d) and entity count — '
        '`just game scene list`.',
    inputSchema: Schema.object(),
    annotations: _readOnly,
  );

  /// `validate_scenes`.
  static final validateScenesTool = Tool(
    name: 'validate_scenes',
    title: "Check the game's scenes",
    description:
        "Check the game's scene files without changing them: each parses, "
        'its format is one this engine reads, entity names are unique, '
        'parents exist, components have a type and prefab instances name a '
        'file — `just game scene validate`. Run it after writing or '
        'changing a scene file.',
    inputSchema: Schema.object(
      properties: {
        'scenes': Schema.list(
          description: 'Scene names to check (default all).',
          items: Schema.string(),
        ),
      },
    ),
    annotations: _readOnly,
  );

  /// `check_game`.
  static final checkGameTool = Tool(
    name: 'check_game',
    title: "Check the game's setup",
    description:
        "The game's setup and release safety: the editor kept to debug "
        'builds and out of the game entry point, engine and SDK versions, '
        'git ignores, and saved files in formats this engine reads — '
        '`just game doctor` and `just game check`. Run it after changing '
        'entry points, the pubspec or saved files; it can take half a '
        'minute.',
    inputSchema: Schema.object(),
    annotations: _readOnly,
  );

  /// What the server tells the assistant when it connects.
  static String instructionsFor(GameKnowledge k) {
    final versions = [
      for (final name in const [
        'just_game_engine',
        'just_game_engine_editor',
        'just_physics_engine',
        'just_inputs',
      ])
        if (k.packages[name] case final p?) '${p.name} ${p.version}',
    ];
    return '''
This is a game made with the Just Game Engine${versions.isEmpty ? '' : ' (${versions.join(', ')})'}, a Flutter game engine.
The engine is new, and its 2.x API differs from 1.x and from other Flutter engines such as Flame: do not guess it.
Before writing engine code, look it up: search_docs for how-tos, get_api for exact signatures and the import to use, read_doc for a whole guide.
After changing scene files, run validate_scenes; after changing entry points, the pubspec or saved files, run check_game.

Rules that trip people up:
- `Engine()` makes a new engine each call: make one and keep the reference (there is no `Engine.instance`). Find a subsystem with `engine.subsystem<T>()` (`Engine.getSystem` is gone).
- Data goes in components (classes extending `Component`), logic in systems (`System` subclasses) that query them. One component of each type per entity; every shape and sprite is a `RenderableComponent`, so a second drawing goes on a child entity.
- The world updates in fixed steps of 1/60 s: move things in `update(deltaTime)`, never by the wall clock. Systems run by priority, highest first (`SystemPriorities`), not in the order added.
- +Y is down: gravity is +Y, a jump is -Y, a positive angle turns clockwise.
- `TransformComponent` is in world space; a child's offset from its parent lives in its `ParentComponent`.
- Levels are `assets/scenes/<name>.scene.json`, listed in play order in `assets/scenes/scenes.json`. The level editor writes them; while it has the game open it saves over changes made to them on disk.
- The editor runs only from the editor entry point (lib/main_editor.dart), inside `if (kDebugMode)`; the game's entry point (lib/main.dart) never imports editor code, so releases hold none.''';
  }

  FutureOr<CallToolResult> _projectInfo(CallToolRequest request) async {
    final b = StringBuffer()
      ..writeln('Game folder: ${knowledge.projectRoot}')
      ..writeln(
        'Level editor: ${_editorOpen() ? 'open (it saves over scene files changed on disk)' : 'not open'}',
      )
      ..writeln();
    if (knowledge.packages.isEmpty) {
      b.writeln(
        'No engine packages resolved: run `flutter pub get` in the game, '
        'then restart this server.',
      );
    } else {
      b.writeln(
        'Engine packages (the versions the docs and API here are for):',
      );
      final names = knowledge.packages.keys.toList()..sort();
      for (final n in names) {
        final p = knowledge.packages[n]!;
        final game = '${knowledge.projectRoot.replaceAll(r'\', '/')}/';
        final where =
            p.root.contains('/Pub/Cache/') || p.root.contains('/.pub-cache/')
            ? 'pub.dev'
            : 'local checkout '
                  '${p.root.startsWith(game) ? p.root.substring(game.length) : p.root}';
        b.writeln('- ${p.name} ${p.version} ($where)');
      }
    }
    b
      ..writeln()
      ..writeln(
        knowledge.guides.isEmpty
            ? 'Guides: none in this just_game_engine version; read them at '
                  'https://engine.justunknown.com/docs (they may be newer).'
            : 'Guides: ${knowledge.guides.length}, from just_game_engine '
                  '${knowledge.engine?.version} (read_doc lists them).',
      );
    final scenes = await runJust(['game', 'scene', 'list']);
    b
      ..writeln()
      ..writeln('Scenes (assets/scenes/, in play order):')
      ..writeln(_sceneLines(scenes));
    return _text(b.toString());
  }

  FutureOr<CallToolResult> _searchDocs(CallToolRequest request) async {
    final args = request.arguments ?? const {};
    final query = (args['query'] as String? ?? '').trim();
    if (query.isEmpty) return _error('Give a query.');
    final kind = args['kind'] as String? ?? 'all';
    final limit = (args['limit'] as int? ?? 8).clamp(1, 25);
    final index = await knowledge.search;
    final hits = index.search(
      query,
      limit: limit,
      kinds: kind == 'all' ? null : {kind},
    );
    if (hits.isEmpty) {
      return _text(
        'Nothing found for "$query". Try other words, a type name, or '
        'read_doc with no arguments for the list of guides.',
      );
    }
    final b = StringBuffer('${hits.length} hits for "$query":\n');
    var n = 0;
    for (final (:entry, score: _) in hits) {
      n++;
      final call = entry.kind == 'api'
          ? 'get_api(symbol: "${entry.ref['symbol']}")'
          : 'read_doc(doc: "${entry.ref['doc']}"'
                '${entry.ref['section'] == null ? '' : ', section: "${entry.ref['section']}"'})';
      b
        ..writeln()
        ..writeln('$n. [${entry.kind}] ${entry.title}  →  $call')
        ..writeln('   ${snippet(entry.text, query)}');
    }
    return _text(b.toString());
  }

  FutureOr<CallToolResult> _readDoc(CallToolRequest request) {
    final args = request.arguments ?? const {};
    final name = (args['doc'] as String? ?? '').trim();
    final section = (args['section'] as String? ?? '').trim();
    if (name.isEmpty) return _text(_docList());
    final guide = knowledge.guide(name);
    final doc = guide?.doc ?? knowledge.note(name);
    if (doc == null) {
      return _error('No guide or note "$name".\n\n${_docList()}');
    }
    final header = guide == null
        ? '<!-- $name -->\n'
        : '<!-- guide "${guide.slug}" (${guide.section}), just_game_engine '
              '${knowledge.engine?.version}; on the web: '
              'https://engine.justunknown.com/docs/${guide.slug} -->\n';
    if (section.isEmpty) return _text('$header${doc.text}');
    final s = doc.section(section);
    if (s == null) {
      return _error(
        'No section "$section" in $name. Its sections:\n'
        '${doc.sections.where((s) => s.heading.isNotEmpty).map((s) => '- ${s.heading}').join('\n')}',
      );
    }
    return _text('$header## ${s.heading}\n\n${s.body}');
  }

  String _docList() {
    final b = StringBuffer();
    if (knowledge.guides.isEmpty) {
      b.writeln(
        'This just_game_engine version ships no guides; read them at '
        'https://engine.justunknown.com/docs.',
      );
    } else {
      b.writeln(
        'Guides (just_game_engine ${knowledge.engine?.version}) — '
        'read_doc(doc: "<slug>"):',
      );
      String? section;
      for (final g in knowledge.guides) {
        if (g.section != section) {
          section = g.section;
          b
            ..writeln()
            ..writeln('$section:');
        }
        b.writeln('- ${g.slug}: ${g.title}. ${g.summary}');
      }
    }
    final notes = knowledge.notes.keys.toList()..sort();
    if (notes.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Package notes — read_doc(doc: "<package/FILE.md>"):')
        ..writeln(notes.map((n) => '- $n').join('\n'));
    }
    return b.toString();
  }

  FutureOr<CallToolResult> _getApi(CallToolRequest request) async {
    final args = request.arguments ?? const {};
    final symbol = (args['symbol'] as String? ?? '').trim();
    if (symbol.isEmpty) return _error('Give a symbol.');
    final package = args['package'] as String?;
    final api = await knowledge.api;
    final found = api.lookup(symbol, package: package);
    if (found.isEmpty) {
      final near = api.similar(symbol);
      return _error(
        'No public API named "$symbol"'
        '${package == null ? '' : ' in $package'}.'
        '${near.isEmpty ? ' Try search_docs.' : ' Closest: ${near.join(', ')}.'}',
      );
    }
    final b = StringBuffer();
    _describe(b, found.first, api);
    if (found.length > 1) {
      b
        ..writeln()
        ..writeln('Also named "$symbol" (get_api with the full name):');
      for (final d in found.skip(1).take(20)) {
        b.writeln(
          '- ${d.kind} ${d.qualifiedName} (${d.package})'
          '${d.summary.isEmpty ? '' : ' — ${d.summary}'}',
        );
      }
      if (found.length > 21) b.writeln('- … ${found.length - 21} more');
    }
    return _text(b.toString());
  }

  void _describe(StringBuffer b, ApiDeclaration d, ApiIndex api) {
    final owner = d.container == null
        ? null
        : api
              .lookup(d.container!, package: d.package)
              .where((o) => o.isType)
              .firstOrNull;
    final libraries = (owner ?? d).libraries;
    final version = knowledge.packages[d.package]?.version ?? '';
    b
      ..writeln('# ${d.kind} ${d.qualifiedName}')
      ..writeln()
      ..writeln('Package: ${d.package} $version — ${d.file}:${d.line}');
    if (libraries.isNotEmpty) {
      b.writeln("Import: import '${libraries.first}';");
    }
    if (d.deprecated != null) b.writeln('**Deprecated:** ${d.deprecated}');
    if (owner != null && d.container != null) {
      b.writeln('Member of: ${owner.kind} ${owner.name}');
    }
    b
      ..writeln()
      ..writeln('```dart')
      ..writeln(d.signature)
      ..writeln('```');
    if (d.doc.isNotEmpty) {
      b
        ..writeln()
        ..writeln(d.doc);
    }
    if (d.values.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Values: ${d.values.join(', ')}');
    }
    if (!d.isType) return;
    final ctors = d.members.where((m) => m.kind == 'constructor').toList();
    final own = d.members
        .where((m) => m.kind != 'constructor' && !m.isOverride)
        .toList();
    final overrides = d.members.where((m) => m.isOverride).toList();
    if (ctors.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Constructors');
      for (final c in ctors) {
        b
          ..writeln()
          ..writeln('```dart')
          ..writeln(c.signature)
          ..writeln('```');
        if (c.deprecated != null) b.writeln('**Deprecated:** ${c.deprecated}');
        if (c.doc.isNotEmpty) b.writeln(c.doc);
      }
    }
    if (own.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Members (get_api "${d.name}.<member>" for one in full)')
        ..writeln();
      for (final m in own) {
        final note = [
          if (m.deprecated != null) 'DEPRECATED: ${m.deprecated}',
          if (m.summary.isNotEmpty) m.summary,
        ].join(' ');
        b.writeln('- `${m.signature}`${note.isEmpty ? '' : ' — $note'}');
      }
    }
    if (overrides.isNotEmpty) {
      b
        ..writeln()
        ..writeln(
          'Overrides: ${overrides.map((m) => m.name).toSet().join(', ')}',
        );
    }
    final subtypes = api.subtypesOf(d.name);
    if (subtypes.isNotEmpty) {
      b
        ..writeln()
        ..writeln(
          'Public subtypes and extensions (${subtypes.length}): '
          '${subtypes.take(60).map((s) => s.name).join(', ')}'
          '${subtypes.length > 60 ? ', …' : ''}',
        );
    }
  }

  FutureOr<CallToolResult> _listScenes(CallToolRequest request) async {
    final run = await runJust(['game', 'scene', 'list']);
    return _text(_sceneLines(run), isError: run.exitCode != 0);
  }

  FutureOr<CallToolResult> _validateScenes(CallToolRequest request) async {
    final names =
        (request.arguments?['scenes'] as List?)?.cast<String>() ?? const [];
    final run = await runJust(['game', 'scene', 'validate', ...names]);
    return _text(
      _report('just game scene validate', run),
      isError: run.exitCode != 0,
    );
  }

  FutureOr<CallToolResult> _checkGame(CallToolRequest request) async {
    final doctor = await runJust(['game', 'doctor']);
    final check = await runJust(['game', 'check']);
    return _text(
      '${_report('just game doctor', doctor)}\n${_report('just game check', check)}',
      isError: doctor.exitCode != 0 || check.exitCode != 0,
    );
  }

  String _sceneLines(JustRun run) {
    final result = _result(run.document);
    if (result is List) {
      if (result.isEmpty) return 'No scenes yet.';
      return [
        for (final row in result)
          if (row is Map)
            '- ${[for (final e in row.entries) '${e.key}: ${e.value}'].join(', ')}'
          else
            '- $row',
      ].join('\n');
    }
    return _report('just game scene list', run);
  }

  /// [run] for the assistant: ok or not, its findings or result, and what
  /// it said.
  String _report(String command, JustRun run) {
    final b = StringBuffer(
      '$command: ${run.exitCode == 0 ? 'ok' : 'problems (exit ${run.exitCode})'}\n',
    );
    final result = _result(run.document);
    if (result case {'findings': final List<Object?> findings}) {
      for (final f in findings) {
        if (f case {'severity': final s, 'message': final m}) {
          final fix = f['fix'];
          b.writeln('- [$s] $m${fix == null ? '' : ' Fix: $fix'}');
        }
      }
    } else if (result case {'scenes': final Map<Object?, Object?> scenes}) {
      for (final MapEntry(key: name, value: problems) in scenes.entries) {
        final list = problems is List ? problems : const [];
        b.writeln(list.isEmpty ? '- $name: ok' : '- $name: ${list.join('; ')}');
      }
      if (result['missing'] case final List<Object?> missing
          when missing.isNotEmpty) {
        b.writeln('- listed in scenes.json but missing: ${missing.join(', ')}');
      }
    } else if (result case {'formats': final List<Object?> formats}) {
      if (result['release-imports'] case {
        'entry': final entry,
        'reachable': final List<Object?> reachable,
      }) {
        b.writeln(
          reachable.isEmpty
              ? '- release-imports: $entry reaches no editor code'
              : '- release-imports: $entry reaches editor code: '
                    '${reachable.join(', ')}',
        );
      }
      final old = [
        for (final f in formats)
          if (f case {
            'path': final p,
            'version': final v,
            'current': final c,
          } when v != c)
            '$p (v$v, current v$c)',
      ];
      b.writeln(
        old.isEmpty
            ? '- formats: ${formats.length} saved files, all in the current format'
            : '- formats: older than this engine writes (`just game migrate` '
                  'updates them): ${old.join(', ')}',
      );
    } else if (result != null) {
      b.writeln(const JsonEncoder.withIndent('  ').convert(result));
    }
    if (run.document case {'error': final Object error}) {
      b.writeln('Error: $error');
    }
    final said = run.messages.trim();
    if (said.isNotEmpty) b.writeln(said);
    return b.toString().trimRight();
  }

  static Object? _result(Object? document) =>
      document is Map ? document['result'] : null;

  static CallToolResult _text(String text, {bool isError = false}) =>
      CallToolResult(
        content: [TextContent(text: text)],
        isError: isError ? true : null,
      );

  static CallToolResult _error(String text) => _text(text, isError: true);
}
