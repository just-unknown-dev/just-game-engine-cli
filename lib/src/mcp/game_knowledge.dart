/// What a game's AI assistant may read: the guides and notes of the engine
/// packages the game resolved, and their API — at exactly those versions,
/// from where pub put them (the pub cache, or a checkout `just dev link`
/// points at).
library;

import 'dart:io';
import 'dart:isolate';

import 'package:just_core_cli/project.dart';
import 'package:meta/meta.dart';

import 'api_index.dart';
import 'search_index.dart';

/// One of the game's engine packages, as pub resolved it.
@internal
final class EnginePackage {
  /// [name] at [version], in [root]; [fromPubCache] when pub took it from
  /// a package server.
  const EnginePackage(
    this.name,
    this.version,
    this.root, {
    this.fromPubCache = false,
  });

  /// The package's name: `just_game_engine`.
  final String name;

  /// Its version, from its pubspec; empty when it gives none.
  final String version;

  /// Its folder, with `/` between parts.
  final String root;

  /// Whether it lives in pub's shared cache (from pub.dev, say), not in a
  /// checkout ([ResolvedPackage.isInPubCache]).
  final bool fromPubCache;
}

/// A Markdown document cut at its `## ` headings, code blocks left whole.
@internal
final class MarkdownDoc {
  /// [text] under [title], cut into [sections].
  MarkdownDoc(this.title, this.text) : sections = _sections(text);

  /// What it is called: the guide's title, or `just_game_engine/MIGRATION.md`.
  final String title;

  /// All of it.
  final String text;

  /// Its sections in order: the text before the first heading (named after
  /// the document), then each `## ` heading and what follows it.
  final List<({String heading, String body})> sections;

  /// The section [heading] names: the same heading, else one starting with
  /// it, else one containing it, else one with a `###` heading or text
  /// that does (any case, `-` read as a space); null for none.
  ({String heading, String body})? section(String heading) {
    String plain(String s) =>
        s.toLowerCase().replaceAll('-', ' ').replaceAll(RegExp(r'\s+'), ' ');
    final h = plain(heading.trim().replaceAll(RegExp(r'^#+\s*'), ''));
    if (h.isEmpty) return null;
    for (final test in <bool Function(({String heading, String body}))>[
      (s) => plain(s.heading) == h,
      (s) => plain(s.heading).startsWith(h),
      (s) => plain(s.heading).contains(h),
      (s) => RegExp(
        r'^###+ (.*)$',
        multiLine: true,
      ).allMatches(s.body).any((m) => plain(m[1]!).contains(h)),
      (s) => plain(s.body).contains(h),
    ]) {
      for (final s in sections) {
        if (s.heading.isNotEmpty && test(s)) return s;
      }
    }
    return null;
  }

  static List<({String heading, String body})> _sections(String text) {
    final out = <({String heading, String body})>[];
    var heading = '';
    final body = StringBuffer();
    var fenced = false;
    void flush() {
      if (body.toString().trim().isNotEmpty || heading.isNotEmpty) {
        out.add((heading: heading, body: body.toString().trim()));
      }
      body.clear();
    }

    for (final line in text.split('\n')) {
      if (line.trimLeft().startsWith('```')) fenced = !fenced;
      if (!fenced && line.startsWith('## ')) {
        flush();
        heading = line.substring(3).trim();
        continue;
      }
      body.writeln(line);
    }
    flush();
    return out;
  }
}

/// A guide from `doc/guides/` of just_game_engine.
@internal
final class Guide {
  /// The guide at `doc/guides/[slug].md`.
  Guide(this.slug, this.section, this.summary, this.doc);

  /// Its name in the docs site's address: `physics-2d`.
  final String slug;

  /// The docs site's section: `Gameplay`.
  final String section;

  /// What it covers, in a sentence.
  final String summary;

  /// Its text.
  final MarkdownDoc doc;

  /// Its title.
  String get title => doc.title;
}

/// The engine packages a game resolved, their guides and notes, and — read
/// in the background, as it takes a moment — their API and a search over
/// all of it.
@internal
final class GameKnowledge {
  GameKnowledge._(this.projectRoot, this.packages, this.guides, this.notes) {
    final roots = {
      for (final p in packages.values)
        if (!_tools.contains(p.name)) p.name: p.root,
    };
    api = _loadApi(roots);
    search = api.then(_buildSearch);
  }

  /// Reads what the game at [projectRoot] resolved. A game pub has not run
  /// in has no packages (and so no guides or API) until it has.
  factory GameKnowledge.read(String projectRoot) {
    final config = PackageConfig.read(projectRoot);
    final ownName = PubspecFields.name(
      _readText('$projectRoot/pubspec.yaml') ?? '',
    );
    final packages = <String, EnginePackage>{};
    for (final p in config?.packages.values ?? const <ResolvedPackage>[]) {
      if (!p.name.startsWith('just_') || p.name == ownName) continue;
      final root = p.rootPath
          .replaceAll(r'\', '/')
          .replaceAll(RegExp(r'/+$'), '');
      packages[p.name] = EnginePackage(
        p.name,
        p.declaredVersion ?? '',
        root,
        fromPubCache: p.isInPubCache,
      );
    }
    final engine = packages['just_game_engine'];
    final guides = engine == null ? <Guide>[] : _readGuides(engine.root);
    final notes = <String, MarkdownDoc>{};
    for (final p in packages.values) {
      if (_tools.contains(p.name)) continue;
      final dir = Directory(p.root);
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        if (!name.toLowerCase().endsWith('.md') || _skipNotes.contains(name)) {
          continue;
        }
        final text = _readText(f.path);
        if (text == null) continue;
        final key = '${p.name}/$name';
        notes[key] = MarkdownDoc(key, text);
      }
    }
    return GameKnowledge._(projectRoot, packages, guides, notes);
  }

  /// The game's folder.
  final String projectRoot;

  /// Its `just_*` packages by name, the game itself left out.
  final Map<String, EnginePackage> packages;

  /// just_game_engine's guides, in the docs site's order; empty for a
  /// version that ships none.
  final List<Guide> guides;

  /// The packages' own Markdown files — README, CHANGELOG, MIGRATION, … —
  /// by `package/FILE.md`.
  final Map<String, MarkdownDoc> notes;

  /// The packages' public API, the command-line tools' left out.
  late final Future<ApiIndex> api;

  /// A search over the guides, the notes and the API.
  late final Future<SearchIndex> search;

  /// just_game_engine, when the game resolved it.
  EnginePackage? get engine => packages['just_game_engine'];

  /// The guide [slug] names (any case), or null.
  Guide? guide(String slug) {
    final s = slug.trim().toLowerCase().replaceAll(RegExp(r'\.md$'), '');
    for (final g in guides) {
      if (g.slug == s) return g;
    }
    return null;
  }

  /// The note `package/FILE.md` [key] names (any case), or null.
  MarkdownDoc? note(String key) {
    final k = key.trim().toLowerCase();
    for (final MapEntry(key: name, value: doc) in notes.entries) {
      if (name.toLowerCase() == k) return doc;
    }
    return null;
  }

  /// The API of the packages at [roots], read in an isolate. It never
  /// fails: nothing listens to it until a tool asks, and an error there
  /// would end the server. What can't be read is in [ApiIndex.problems].
  static Future<ApiIndex> _loadApi(Map<String, String> roots) async {
    try {
      return await Isolate.run(() => ApiIndex.read(roots));
    } on Object {
      // Where an isolate can't start, read it here.
      try {
        return ApiIndex.read(roots);
      } on Object catch (e) {
        return ApiIndex.unread(roots.keys, 'The API could not be read: $e');
      }
    }
  }

  SearchIndex _buildSearch(ApiIndex api) {
    final entries = <SearchEntry>[];
    for (final g in guides) {
      for (final s in g.doc.sections) {
        entries.add(
          SearchEntry(
            kind: 'guide',
            title: s.heading.isEmpty ? g.title : '${g.title} › ${s.heading}',
            text: s.body,
            ref: {
              'doc': g.slug,
              if (s.heading.isNotEmpty) 'section': s.heading,
            },
            // Written for people, and longer than an API entry, which
            // BM25 would otherwise favour.
            boost: 2.2,
          ),
        );
      }
    }
    for (final MapEntry(key: key, value: doc) in notes.entries) {
      for (final s in doc.sections) {
        entries.add(
          SearchEntry(
            kind: 'notes',
            title: s.heading.isEmpty ? key : '$key › ${s.heading}',
            text: s.body,
            ref: {'doc': key, if (s.heading.isNotEmpty) 'section': s.heading},
            boost: key.endsWith('CHANGELOG.md') ? 0.6 : 1.0,
          ),
        );
      }
    }
    for (final d in api.declarations) {
      entries.add(_apiEntry(d, 1.2));
      for (final m in d.members) {
        if (!m.isOverride) entries.add(_apiEntry(m, 1.0));
      }
    }
    return SearchIndex(entries);
  }

  static SearchEntry _apiEntry(ApiDeclaration d, double boost) => SearchEntry(
    kind: 'api',
    title: d.qualifiedName,
    text: [
      d.signature,
      d.doc,
      if (d.isType) d.members.map((m) => m.name).join(' '),
      if (d.values.isNotEmpty) d.values.join(' '),
    ].join('\n'),
    ref: {'symbol': d.qualifiedName, 'package': d.package},
    boost: d.deprecated != null ? boost * 0.4 : boost,
  );
}

// The command-line tools: no API a game calls.
const _tools = {'just_core_cli', 'just_game_engine_cli'};

const _skipNotes = {'LICENSE.md', 'CODE_OF_CONDUCT.md', 'CONTRIBUTING.md'};

List<Guide> _readGuides(String engineRoot) {
  final dir = '$engineRoot/doc/guides';
  final index = _readText('$dir/README.md');
  if (index == null) return [];
  final out = <Guide>[];
  String? section;
  final entry = RegExp(r'^- \[(.+?)\]\(([\w-]+)\.md\):\s*(.*)$');
  for (final line in index.split('\n').map((l) => l.trimRight())) {
    if (line.startsWith('## ')) {
      section = line.substring(3).trim();
      continue;
    }
    final m = entry.firstMatch(line);
    if (m == null || section == null) continue;
    final text = _readText('$dir/${m[2]}.md');
    if (text == null) continue;
    out.add(Guide(m[2]!, section, m[3]!, MarkdownDoc(m[1]!, text)));
  }
  return out;
}

String? _readText(String path) {
  try {
    return File(path).readAsStringSync().replaceAll('\r\n', '\n');
  } on FileSystemException {
    return null;
  }
}
