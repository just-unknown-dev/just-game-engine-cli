/// The public API of Dart packages, read from their source: each
/// declaration a game can import, its signature and doc comment, and the
/// library to import it from.
///
/// A light reader, not an analyzer: it finds declarations by their shape —
/// enough to look up a signature and its docs — and needs no dependency
/// that could clash with a game's own (it runs in the game's resolution).
library;

import 'dart:io';

/// A public declaration: a type, a top-level function or variable, or a
/// member of a type.
final class ApiDeclaration {
  /// [name] of [kind], declared at [line] of [file] in [package].
  ApiDeclaration({
    required this.package,
    required this.name,
    required this.kind,
    required this.signature,
    required this.doc,
    required this.file,
    required this.line,
    this.container,
    this.supertypes = const [],
    this.deprecated,
    this.isOverride = false,
  });

  /// The package that declares it.
  final String package;

  /// Its name: `CharacterBody2DComponent`, `moveAndSlide`; a constructor's is the
  /// type's (`Engine`) or the type's and its own (`Engine.headless`).
  final String name;

  /// What it is: class, mixin, enum, extension, extension type, typedef,
  /// function, variable, constructor, method, getter, setter, field or
  /// operator.
  final String kind;

  /// Its declaration without a body: `void update(double deltaTime)`.
  final String signature;

  /// Its doc comment, as Markdown; empty for none.
  final String doc;

  /// The file, relative to the package (`lib/src/ecs/world.dart`).
  final String file;

  /// The line it starts on.
  final int line;

  /// The type a member belongs to.
  final String? container;

  /// What a type extends, mixes in, implements or is on.
  final List<String> supertypes;

  /// The `@Deprecated` message, when it is deprecated.
  final String? deprecated;

  /// Whether it is marked `@override`.
  final bool isOverride;

  /// A type's members, in source order.
  final List<ApiDeclaration> members = [];

  /// An enum's values.
  final List<String> values = [];

  /// The libraries a game can import it from, best first.
  final List<String> libraries = [];

  /// Whether it declares a type.
  bool get isType => const {
    'class',
    'mixin',
    'enum',
    'extension',
    'extension type',
  }.contains(kind);

  /// `Type.member`, or the name of a top-level declaration or constructor.
  String get qualifiedName =>
      container == null || kind == 'constructor' ? name : '$container.$name';

  /// The doc comment's first sentence (or line), for lists.
  String get summary {
    final first = doc.split(RegExp(r'\n\s*\n')).first.replaceAll('\n', ' ');
    final end = RegExp(r'\.(\s|$)').firstMatch(first);
    return (end == null ? first : first.substring(0, end.start + 1)).trim();
  }
}

/// An `export` directive: [uri] with its `show` and `hide` names.
final class DartExport {
  /// An export of [uri] showing [show] (null for all) and hiding [hide].
  const DartExport(this.uri, {this.show, this.hide = const {}});

  /// The exported library, as written.
  final String uri;

  /// The names it shows; null when it shows everything.
  final Set<String>? show;

  /// The names it hides.
  final Set<String> hide;
}

/// What one Dart file declares and exports, and the parts it includes.
final class DartFileScan {
  /// The scan of a file.
  const DartFileScan(
    this.declarations,
    this.exports,
    this.parts, {
    this.isPart = false,
  });

  /// Whether it is a part of another library (`part of`).
  final bool isPart;

  /// Its public top-level declarations, members included.
  final List<ApiDeclaration> declarations;

  /// Its `export` directives.
  final List<DartExport> exports;

  /// Its `part` files, as written.
  final List<String> parts;
}

/// Reads the public declarations, exports and parts of [source], the file
/// at [file] in [package].
DartFileScan scanDartSource(
  String source, {
  required String package,
  required String file,
}) => _Scanner(source, package, file).scan();

/// The public API of a set of packages: what each package's libraries
/// (`lib/*.dart`) export, through every export and part, other packages'
/// included.
final class ApiIndex {
  ApiIndex._(this.declarations, this.packages);

  /// Reads the packages at [roots] (package name → its folder). A package
  /// without a `lib/` is left out.
  factory ApiIndex.read(Map<String, String> roots) {
    final scans = <String, DartFileScan>{};
    final libraries = <String, List<String>>{};
    for (final MapEntry(key: package, value: root) in roots.entries) {
      final lib = Directory(
        '${_slashes(root).replaceAll(RegExp(r'/+$'), '')}/lib',
      );
      if (!lib.existsSync()) continue;
      for (final f in lib.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final rel = _relative(root, f.path);
        final String text;
        try {
          text = f.readAsStringSync();
        } on FileSystemException {
          continue;
        }
        final scan = scans['$package:$rel'] = scanDartSource(
          text,
          package: package,
          file: rel,
        );
        if (!rel.substring(4).contains('/') && !scan.isPart) {
          (libraries[package] ??= []).add(rel);
        }
      }
    }
    final public = <ApiDeclaration>{};
    for (final MapEntry(key: package, value: libs) in libraries.entries) {
      for (final lib in libs) {
        final uri = 'package:$package/${lib.substring(4)}';
        _walk(scans, '$package:$lib', _Filter.all, uri, public, {});
      }
    }
    for (final d in public) {
      d.libraries.sort(
        (a, b) =>
            _libraryRank(a, d.package).compareTo(_libraryRank(b, d.package)),
      );
    }
    return ApiIndex._(public.toList(), roots.keys.toList());
  }

  /// Every public top-level declaration (types with their members).
  final List<ApiDeclaration> declarations;

  /// The packages read.
  final List<String> packages;

  late final Map<String, List<ApiDeclaration>> _byName = () {
    final map = <String, List<ApiDeclaration>>{};
    void add(ApiDeclaration d) =>
        (map[d.qualifiedName.toLowerCase()] ??= []).add(d);
    for (final d in declarations) {
      add(d);
      for (final m in d.members) {
        add(m);
        if (m.kind != 'constructor') {
          (map[m.name.toLowerCase()] ??= []).add(m);
        }
      }
    }
    return map;
  }();

  late final Map<String, List<ApiDeclaration>> _subtypes = () {
    final map = <String, List<ApiDeclaration>>{};
    for (final d in declarations) {
      for (final s in d.supertypes) {
        (map[s] ??= []).add(d);
      }
    }
    return map;
  }();

  /// What [query] names: `CharacterBody2DComponent`, `World.query`, `subsystem`. A
  /// type before its members' namesakes; [package] narrows it.
  List<ApiDeclaration> lookup(String query, {String? package}) {
    final key = query
        .trim()
        .replaceAll(RegExp(r'[(<].*$'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .toLowerCase();
    final found = [...?_byName[key]];
    if (package != null) found.retainWhere((d) => d.package == package);
    found.sort((a, b) {
      final byType = (b.isType ? 1 : 0) - (a.isType ? 1 : 0);
      if (byType != 0) return byType;
      final byTop =
          (a.container == null ? 0 : 1) - (b.container == null ? 0 : 1);
      if (byTop != 0) return byTop;
      return a.qualifiedName.length - b.qualifiedName.length;
    });
    return found;
  }

  /// Names close to [query], for a lookup that found nothing.
  List<String> similar(String query, {int limit = 8}) {
    final q = query.toLowerCase();
    final scored = <(String, int)>[];
    for (final key in _byName.keys) {
      final d = _byName[key]!.first;
      final score = key.contains(q) || q.contains(key)
          ? (key.length - q.length).abs()
          : _distance(key, q);
      if (score <= (q.length / 3).ceil() + 1 || key.contains(q)) {
        scored.add((d.qualifiedName, score));
      }
    }
    scored.sort((a, b) => a.$2.compareTo(b.$2));
    return {for (final s in scored) s.$1}.take(limit).toList();
  }

  /// The public types that extend, mix in, implement or are on [type].
  List<ApiDeclaration> subtypesOf(String type) => [...?_subtypes[type]];
}

// Library choice: the engine's barrel, then the package's own, then the
// rest, shortest first.
int _libraryRank(String uri, String package) {
  if (uri == 'package:just_game_engine/just_game_engine.dart') return 0;
  if (uri == 'package:$package/$package.dart') return 1;
  return 2 + uri.length;
}

/// What an export chain lets through.
final class _Filter {
  const _Filter(this.show, this.hide);

  static const all = _Filter(null, {});

  final Set<String>? show;
  final Set<String> hide;

  bool allows(String name) =>
      !hide.contains(name) && (show == null || show!.contains(name));

  _Filter then(DartExport e) => _Filter(
    show == null
        ? e.show
        : e.show == null
        ? show
        : show!.intersection(e.show!),
    {...hide, ...e.hide},
  );

  String get key => '${show?.toList()?..sort()}|${hide.toList()..sort()}';
}

void _walk(
  Map<String, DartFileScan> scans,
  String fileKey,
  _Filter filter,
  String library,
  Set<ApiDeclaration> public,
  Set<String> seen,
) {
  if (!seen.add('$fileKey#${filter.key}')) return;
  final scan = scans[fileKey];
  if (scan == null) return;
  for (final d in scan.declarations) {
    if (!filter.allows(d.name)) continue;
    public.add(d);
    if (!d.libraries.contains(library)) d.libraries.add(library);
  }
  for (final part in scan.parts) {
    final target = _resolve(fileKey, part);
    if (target != null) _walk(scans, target, filter, library, public, seen);
  }
  for (final e in scan.exports) {
    final target = _resolve(fileKey, e.uri);
    if (target != null) {
      _walk(scans, target, filter.then(e), library, public, seen);
    }
  }
}

/// [uri] as written in the file [fileKey] (`package:lib/src/a.dart`), as a
/// file key; null for a `dart:` library.
String? _resolve(String fileKey, String uri) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    return '${rest.substring(0, slash)}:lib/${rest.substring(slash + 1)}';
  }
  final colon = fileKey.indexOf(':');
  final package = fileKey.substring(0, colon);
  final path = fileKey.substring(colon + 1);
  final dir = path.contains('/')
      ? path.substring(0, path.lastIndexOf('/'))
      : '';
  final parts = [...dir.split('/'), ...uri.split('/')];
  final out = <String>[];
  for (final p in parts) {
    if (p == '..') {
      if (out.isNotEmpty) out.removeLast();
    } else if (p != '.' && p.isNotEmpty) {
      out.add(p);
    }
  }
  return '$package:${out.join('/')}';
}

String _relative(String root, String path) {
  final r = _slashes(root).replaceAll(RegExp(r'/+$'), '');
  final p = _slashes(path);
  final ignoreCase = Platform.isWindows || Platform.isMacOS;
  final prefix = '$r/';
  final match = ignoreCase
      ? p.toLowerCase().startsWith(prefix.toLowerCase())
      : p.startsWith(prefix);
  return match ? p.substring(prefix.length) : p;
}

String _slashes(String path) =>
    path.replaceAll(r'\', '/').replaceAll(RegExp(r'(?<!^)/{2,}'), '/');

int _distance(String a, String b) {
  if ((a.length - b.length).abs() > 4) return 99;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = [i, ...List<int>.filled(b.length, 0)];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = [
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

// --- The reader ------------------------------------------------------------

const _space = 0x20, _tab = 0x09, _nl = 0x0A, _cr = 0x0D;
const _slash = 0x2F, _star = 0x2A, _backslash = 0x5C, _dollar = 0x24;
const _quote = 0x27, _dquote = 0x22, _r = 0x72;
const _lbrace = 0x7B, _rbrace = 0x7D, _lparen = 0x28, _rparen = 0x29;
const _lbracket = 0x5B, _rbracket = 0x5D, _semi = 0x3B, _eq = 0x3D, _gt = 0x3E;

/// A declaration's text up to its end: `;`, a body's `{`, or the `}` that
/// closes what holds it. [cut] is where `=>` or an initializer's `=` began.
final class _Header {
  const _Header(this.text, this.cut, this.end);

  final String text;
  final int? cut;
  final String end;
}

final class _Scanner {
  _Scanner(this.src, this.package, this.file) {
    for (var k = 0; k < src.length; k++) {
      if (src.codeUnitAt(k) == _nl) _lineStarts.add(k + 1);
    }
  }

  final String src;
  final String package;
  final String file;
  final List<int> _lineStarts = [0];
  final List<DartExport> _exports = [];
  final List<String> _parts = [];
  bool _partOf = false;
  int i = 0;

  DartFileScan scan() {
    final declarations = _body(null);
    return DartFileScan(declarations, _exports, _parts, isPart: _partOf);
  }

  int _lineAt(int offset) {
    var lo = 0, hi = _lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo + 1;
  }

  int _at(int k) => k < src.length ? src.codeUnitAt(k) : -1;

  /// The declarations in a body — the file's, or [owner]'s between its
  /// braces — until its closing brace.
  List<ApiDeclaration> _body(ApiDeclaration? owner) {
    final out = <ApiDeclaration>[];
    var enumValues = owner?.kind == 'enum';
    while (true) {
      final doc = _trivia();
      if (i >= src.length) break;
      if (_at(i) == _rbrace) {
        i++;
        if (owner != null) break;
        continue;
      }
      final start = i;
      final h = _header();
      if (enumValues) {
        enumValues = false;
        owner!.values.addAll(_enumValues(h.text));
        continue;
      }
      final d = _declaration(h, doc, start, owner);
      if (h.end == '{') {
        if (d != null && d.isType) {
          d.members.addAll(_body(d));
        } else {
          _skipBlock(i - 1);
        }
      }
      if (d != null) out.add(d);
    }
    return out;
  }

  /// Whitespace and comments; returns the doc comment just read.
  String _trivia() {
    final doc = <String>[];
    while (i < src.length) {
      final c = _at(i);
      if (c == _space || c == _tab || c == _nl || c == _cr) {
        i++;
      } else if (c == _slash && _at(i + 1) == _slash) {
        final end = src.indexOf('\n', i);
        final line = src.substring(i, end < 0 ? src.length : end);
        i = end < 0 ? src.length : end + 1;
        if (line.startsWith('///') && !line.startsWith('////')) {
          final t = line.substring(3);
          doc.add((t.startsWith(' ') ? t.substring(1) : t).trimRight());
        }
      } else if (c == _slash && _at(i + 1) == _star) {
        final s = i;
        _skipBlockComment();
        final text = src.substring(s, i);
        if (text.startsWith('/**') && text != '/**/') {
          for (final l in text.substring(3, text.length - 2).split('\n')) {
            final t = l.trim();
            doc.add(t.startsWith('*') ? t.substring(1).trim() : t);
          }
        }
      } else {
        break;
      }
    }
    return doc.join('\n').trim();
  }

  _Header _header() {
    final b = StringBuffer();
    var nest = 0, inner = 0;
    int? cut;
    while (i < src.length) {
      final c = _at(i);
      if (c == _slash && _at(i + 1) == _slash) {
        final end = src.indexOf('\n', i);
        i = end < 0 ? src.length : end;
        b.write(' ');
        continue;
      }
      if (c == _slash && _at(i + 1) == _star) {
        _skipBlockComment();
        b.write(' ');
        continue;
      }
      if (_stringStarts()) {
        final s = i;
        _skipString();
        b.write(src.substring(s, i));
        continue;
      }
      switch (c) {
        case _lparen || _lbracket:
          nest++;
        case _rparen || _rbracket:
          if (nest > 0) nest--;
        case _lbrace:
          if (nest > 0) {
            inner++;
          } else if (cut != null) {
            final s = i;
            _skipBlock(i);
            b.write(src.substring(s, i));
            continue;
          } else {
            i++;
            return _Header(b.toString(), cut, '{');
          }
        case _rbrace:
          if (nest == 0 && inner == 0) return _Header(b.toString(), cut, '}');
          if (inner > 0) inner--;
        case _semi when nest == 0:
          i++;
          return _Header(b.toString(), cut, ';');
        case _eq when nest == 0 && cut == null:
          final next = _at(i + 1);
          final text = b.toString().trimRight();
          final prev = text.isEmpty ? -1 : text.codeUnitAt(text.length - 1);
          if (next == _gt) {
            cut = b.length;
          } else if (next == _eq ||
              const [_eq, 0x21, 0x3C, _gt].contains(prev) ||
              _indexSetter.hasMatch(text) ||
              _initializerList.hasMatch(text)) {
            // An operator, or a constructor's initializer list.
          } else {
            cut = b.length;
          }
      }
      b.writeCharCode(c);
      i++;
    }
    return _Header(b.toString(), cut, 'eof');
  }

  bool _stringStarts() {
    final c = _at(i);
    if (c == _quote || c == _dquote) return true;
    if (c != _r) return false;
    final n = _at(i + 1);
    if (n != _quote && n != _dquote) return false;
    final p = i == 0 ? -1 : _at(i - 1);
    return !(p == 0x5F ||
        p == _dollar ||
        (p >= 0x30 && p <= 0x39) ||
        (p >= 0x41 && p <= 0x5A) ||
        (p >= 0x61 && p <= 0x7A));
  }

  void _skipString() {
    var raw = false;
    if (_at(i) == _r) {
      raw = true;
      i++;
    }
    final q = _at(i);
    final triple = _at(i + 1) == q && _at(i + 2) == q;
    i += triple ? 3 : 1;
    while (i < src.length) {
      final c = _at(i);
      if (!raw && c == _backslash) {
        i += 2;
      } else if (!raw && c == _dollar && _at(i + 1) == _lbrace) {
        _skipBlock(i + 1);
      } else if (c == q && (!triple || (_at(i + 1) == q && _at(i + 2) == q))) {
        i += triple ? 3 : 1;
        return;
      } else if (c == _nl && !triple) {
        return;
      } else {
        i++;
      }
    }
  }

  void _skipBlockComment() {
    var depth = 0;
    while (i < src.length) {
      if (_at(i) == _slash && _at(i + 1) == _star) {
        depth++;
        i += 2;
      } else if (_at(i) == _star && _at(i + 1) == _slash) {
        depth--;
        i += 2;
        if (depth == 0) return;
      } else {
        i++;
      }
    }
  }

  /// Skips the braces opened at [open], strings and comments in them
  /// included; leaves [i] after the closing brace.
  void _skipBlock(int open) {
    i = open;
    var depth = 0;
    while (i < src.length) {
      final c = _at(i);
      if (c == _slash && _at(i + 1) == _slash) {
        final end = src.indexOf('\n', i);
        i = end < 0 ? src.length : end;
      } else if (c == _slash && _at(i + 1) == _star) {
        _skipBlockComment();
      } else if (_stringStarts()) {
        _skipString();
      } else {
        if (c == _lbrace) depth++;
        if (c == _rbrace) {
          depth--;
          if (depth == 0) {
            i++;
            return;
          }
        }
        i++;
      }
    }
  }

  List<String> _enumValues(String text) {
    final out = <String>[];
    for (final part in _splitTop(text, ',')) {
      final m = RegExp(
        r'^\s*([A-Za-z]\w*)',
      ).firstMatch(_stripAnnotations(part).text);
      if (m != null) out.add(m[1]!);
    }
    return out;
  }

  ApiDeclaration? _declaration(
    _Header h,
    String doc,
    int start,
    ApiDeclaration? owner,
  ) {
    final full = _squash(h.text);
    final annotated = _stripAnnotations(
      _squash(h.cut == null ? h.text : h.text.substring(0, h.cut)),
    );
    var sig = annotated.text;
    if (sig.isEmpty) return null;
    final line = _lineAt(start);

    ApiDeclaration make(
      String name,
      String kind, {
      String? signature,
      List<String> supertypes = const [],
    }) => ApiDeclaration(
      package: package,
      name: name,
      kind: kind,
      signature: signature ?? sig,
      doc: doc,
      file: file,
      line: line,
      container: owner?.name,
      supertypes: supertypes,
      deprecated: annotated.deprecated,
      isOverride: annotated.isOverride,
    );

    if (owner == null) {
      final directive = _stripAnnotations(full).text;
      if (directive.startsWith('export ')) {
        _export(directive);
        return null;
      }
      if (_partOfDirective.hasMatch(directive)) {
        _partOf = true;
        return null;
      }
      if (_importOrLibrary.hasMatch(directive)) return null;
      if (directive.startsWith('part ')) {
        final uri = _quotedUri.firstMatch(directive);
        if (uri != null) _parts.add(uri[1]!);
        return null;
      }
      final type = _typeDeclaration(_stripAnnotations(full).text);
      if (type != null) {
        final (name, kind, header) = type;
        if (name.startsWith('_')) return null;
        return make(
          name,
          kind,
          signature: header,
          supertypes: _supertypes(header, kind),
        );
      }
    }

    final o = owner;
    if (o != null &&
        (o.kind == 'class' || o.kind == 'enum' || o.kind == 'extension type')) {
      final ctor = RegExp(
        '^(?:(?:const|factory|external)\\s+)*${RegExp.escape(o.name)}'
        r'(?:\.(\w+))?\s*\(',
      ).firstMatch(sig);
      if (ctor != null) {
        final named = ctor[1];
        if (named != null && named.startsWith('_')) return null;
        if (named == null && o.kind == 'enum') return null;
        sig = _withoutInitializers(sig);
        return make(named == null ? o.name : '${o.name}.$named', 'constructor');
      }
    }
    final top = owner == null;
    if (_operatorDecl.firstMatch(sig) case final m?) {
      return make('operator ${m[1]}', 'operator');
    }
    if (_getterDecl.firstMatch(sig) case final m?) {
      return m[1]!.startsWith('_') ? null : make(m[1]!, 'getter');
    }
    if (_setterDecl.firstMatch(sig) case final m?) {
      return m[1]!.startsWith('_') ? null : make(m[1]!, 'setter');
    }
    for (final m in _callableDecl.allMatches(sig)) {
      final name = m[1]!;
      if (name == 'Function') continue;
      if (_keywords.contains(name)) return null;
      return name.startsWith('_')
          ? null
          : make(name, top ? 'function' : 'method');
    }
    final field = _trailingName.firstMatch(sig);
    if (field == null) return null;
    final name = field[1]!;
    if (name.startsWith('_') || _keywords.contains(name)) return null;
    var signature = sig;
    if (h.cut != null && _constWord.hasMatch(sig)) {
      final value = _squash(h.text.substring(h.cut! + 1)).trim();
      if (value.length <= 80) signature = '$sig = $value';
    }
    return make(name, top ? 'variable' : 'field', signature: signature);
  }

  void _export(String directive) {
    final uri = _quotedUri.firstMatch(directive);
    if (uri == null) return;
    Set<String>? names(String word) {
      final m = RegExp(
        '\\b$word\\s+([\\w\\s,]+?)(?=\\s*(?:\\bshow\\b|\\bhide\\b|\$))',
      ).firstMatch(directive);
      if (m == null) return null;
      return {
        for (final n in m[1]!.split(','))
          if (n.trim().isNotEmpty) n.trim(),
      };
    }

    _exports.add(
      DartExport(uri[1]!, show: names('show'), hide: names('hide') ?? {}),
    );
  }
}

const _keywords = {
  'if',
  'for',
  'while',
  'switch',
  'return',
  'assert',
  'super',
  'this',
  'throw',
  'catch',
  'await',
  'yield',
  'new',
  'const',
  'final',
  'var',
  'late',
  'static',
  'external',
  'abstract',
  'covariant',
  'required',
  'void',
  'dynamic',
  'get',
  'set',
  'operator',
  'factory',
};

(String, String, String)? _typeDeclaration(String text) {
  final m = RegExp(
    r'^((?:(?:abstract|base|final|sealed|interface|mixin)\s+)*class\s+(\w+)'
    r'|(?:base\s+)?mixin\s+(\w+)'
    r'|enum\s+(\w+)'
    r'|extension\s+type\s+(?:const\s+)?(\w+)'
    r'|extension\s+(\w+)(?=\s*(?:<[^>]*>)?\s+on\b)'
    r'|typedef\s+(\w+))',
  ).firstMatch(text);
  if (m == null) return null;
  final head = m[1]!;
  final kind = head.contains('class ')
      ? 'class'
      : head.startsWith('enum')
      ? 'enum'
      : head.startsWith('extension type')
      ? 'extension type'
      : head.startsWith('extension')
      ? 'extension'
      : head.startsWith('typedef')
      ? 'typedef'
      : 'mixin';
  final name = [for (var g = 2; g <= 7; g++) m[g]].nonNulls.first;
  return (name, kind, text);
}

List<String> _supertypes(String header, String kind) {
  var h = header;
  // Drop type arguments, innermost first.
  for (var k = 0; k < 8 && h.contains('<'); k++) {
    h = h.replaceAll(RegExp(r'<[^<>]*>'), '');
  }
  final out = <String>[];
  void addList(String? list) {
    if (list == null) return;
    for (final t in list.split(',')) {
      final name = RegExp(r'([A-Za-z_]\w*)\s*$').firstMatch(t.trim())?[1];
      if (name != null) out.add(name);
    }
  }

  final clauses = RegExp(
    r'\b(extends|with|implements|on)\s+(.+?)(?=\s+\b(?:extends|with|implements|on)\b|$)',
  ).allMatches(h);
  for (final c in clauses) {
    addList(c[2]);
  }
  return out;
}

String _withoutInitializers(String sig) {
  // `Foo(this.a) : b = a, super()` → `Foo(this.a)`.
  var depth = 0;
  for (var k = 0; k < sig.length; k++) {
    final c = sig[k];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (depth == 0 && c == ':' && k > 0) return sig.substring(0, k).trim();
  }
  return sig;
}

/// [text] without its annotations; whether one was `@override`, and a
/// `@Deprecated` message.
({String text, bool isOverride, String? deprecated}) _stripAnnotations(
  String text,
) {
  var t = text.trimLeft();
  var isOverride = false;
  String? deprecated;
  while (t.startsWith('@')) {
    final name = RegExp(r'^@([\w.]+)').firstMatch(t);
    if (name == null) break;
    var end = name.end;
    var args = '';
    final rest = t.substring(end);
    if (rest.trimLeft().startsWith('(')) {
      final open = end + rest.indexOf('(');
      var depth = 0;
      for (var k = open; k < t.length; k++) {
        if (t[k] == '(') depth++;
        if (t[k] == ')') {
          depth--;
          if (depth == 0) {
            args = t.substring(open + 1, k);
            end = k + 1;
            break;
          }
        }
      }
    }
    final n = name[1]!;
    if (n == 'override') isOverride = true;
    if (n == 'deprecated') deprecated = 'deprecated';
    if (n == 'Deprecated') {
      deprecated = args
          .replaceAll(RegExp('''^\\s*['"]|['"]\\s*\$'''), '')
          .trim();
      if (deprecated.isEmpty) deprecated = 'deprecated';
    }
    t = t.substring(end).trimLeft();
  }
  return (text: t, isOverride: isOverride, deprecated: deprecated);
}

String _squash(String s) => s.replaceAll(_whitespace, ' ').trim();

final _indexSetter = RegExp(r'\boperator\s*\[\]$');
final _initializerList = RegExp(r'\)\s*:');
final _partOfDirective = RegExp(r'^part\s+of\b');
final _importOrLibrary = RegExp(r'^(import|library)\b');
final _quotedUri = RegExp(r'''['"]([^'"]+)['"]''');
final _operatorDecl = RegExp(r'\boperator\s*(\S+?)\s*\(');
final _getterDecl = RegExp(r'\bget\s+(\w+)\s*$');
final _setterDecl = RegExp(r'\bset\s+(\w+)\s*\(');
final _callableDecl = RegExp(r'(\w+)\s*(?:<[^()]*>)?\s*\(');
final _trailingName = RegExp(r'([A-Za-z_$][\w$]*)\s*$');
final _constWord = RegExp(r'\bconst\b');
final _whitespace = RegExp(r'\s+');

List<String> _splitTop(String s, String sep) {
  final out = <String>[];
  var depth = 0, from = 0;
  for (var k = 0; k < s.length; k++) {
    final c = s[k];
    if ('([{<'.contains(c)) depth++;
    if (')]}>'.contains(c)) depth--;
    if (depth == 0 && c == sep) {
      out.add(s.substring(from, k));
      from = k + 1;
    }
  }
  out.add(s.substring(from));
  return out;
}
