/// Keyword search (BM25) over the guides, the packages' notes and their
/// API: small, offline and exact about names, which is what questions about
/// code ask for.
library;

import 'dart:math' as math;

/// One searchable piece: a guide's section, a note's section, or an API
/// declaration.
final class SearchEntry {
  /// [title] and [text] of [kind], found again by [ref].
  const SearchEntry({
    required this.kind,
    required this.title,
    required this.text,
    required this.ref,
    this.boost = 1.0,
  });

  /// `guide`, `api` or `notes`.
  final String kind;

  /// What a hit is called: `Scenes & saving › Prefabs`,
  /// `CharacterBody2DComponent.moveAndSlide`.
  final String title;

  /// The words searched, and what a snippet is cut from.
  final String text;

  /// How to read all of it: the arguments of `read_doc` or `get_api`.
  final Map<String, String> ref;

  /// A weight on its score: guides first, as written for people.
  final double boost;
}

/// A hit: [entry] and its [score].
typedef SearchHit = ({SearchEntry entry, double score});

/// BM25 over [SearchEntry]s, titles counting three times.
final class SearchIndex {
  /// An index of [entries].
  SearchIndex(List<SearchEntry> entries) : _entries = entries {
    var total = 0;
    for (final e in entries) {
      final counts = <String, int>{};
      for (final t in tokens(e.title)) {
        counts[t] = (counts[t] ?? 0) + 3;
      }
      for (final t in tokens(e.text)) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
      final length = counts.values.fold(0, (a, b) => a + b);
      _counts.add(counts);
      _lengths.add(length);
      total += length;
      for (final t in counts.keys) {
        _df[t] = (_df[t] ?? 0) + 1;
      }
    }
    _average = entries.isEmpty ? 1 : total / entries.length;
  }

  final List<SearchEntry> _entries;
  final List<Map<String, int>> _counts = [];
  final List<int> _lengths = [];
  final Map<String, int> _df = {};
  late final double _average;

  /// How many entries it holds.
  int get length => _entries.length;

  /// The [limit] best entries for [query], of [kinds] when given.
  List<SearchHit> search(String query, {int limit = 8, Set<String>? kinds}) {
    final terms = tokens(query).toSet();
    if (terms.isEmpty) return const [];
    final whole = query.trim().toLowerCase();
    const k1 = 1.2, b = 0.75;
    final n = _entries.length;
    final hits = <SearchHit>[];
    for (var i = 0; i < n; i++) {
      final e = _entries[i];
      if (kinds != null && !kinds.contains(e.kind)) continue;
      final counts = _counts[i];
      var score = 0.0;
      var matched = 0;
      for (final t in terms) {
        final tf = counts[t];
        if (tf == null) continue;
        matched++;
        final df = _df[t]!;
        final idf = math.log(1 + (n - df + 0.5) / (df + 0.5));
        score +=
            idf *
            tf *
            (k1 + 1) /
            (tf + k1 * (1 - b + b * _lengths[i] / _average));
      }
      if (score == 0) continue;
      // Every word found beats some found often; a name typed whole wins.
      score *= 0.5 + 0.5 * matched / terms.length;
      final title = e.title.toLowerCase();
      if (title == whole || title.endsWith('.$whole')) score *= 3;
      hits.add((entry: e, score: score * e.boost));
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList();
  }
}

final _words = RegExp(r'[A-Za-z0-9]+');
final _parts = RegExp(r'[A-Z]+(?![a-z])|[A-Z]?[a-z]+|[0-9]+[A-Za-z]?');

const _stop = {
  'a',
  'an',
  'and',
  'are',
  'as',
  'at',
  'be',
  'by',
  'can',
  'do',
  'does',
  'for',
  'from',
  'how',
  'i',
  'in',
  'is',
  'it',
  'its',
  'my',
  'of',
  'on',
  'or',
  'the',
  'this',
  'that',
  'to',
  'what',
  'when',
  'with',
  'you',
  'your',
};

/// The words of [text], lower case, light-stemmed, with camel case split:
/// `CharacterBody2DComponent` gives `characterbody2d`, `character`, `body` and `2d`.
List<String> tokens(String text) {
  final out = <String>[];
  for (final m in _words.allMatches(text)) {
    final word = m[0]!;
    final lower = word.toLowerCase();
    if (_stop.contains(lower)) continue;
    out.add(_stem(lower));
    final parts = _parts.allMatches(word).map((p) => p[0]!).toList();
    if (parts.length > 1) {
      for (final p in parts) {
        final l = p.toLowerCase();
        if (!_stop.contains(l)) out.add(_stem(l));
      }
    }
  }
  return out;
}

String _stem(String w) {
  if (w.length > 4 && w.endsWith('ies')) {
    return '${w.substring(0, w.length - 3)}y';
  }
  if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) {
    return w.substring(0, w.length - 1);
  }
  return w;
}

/// Up to [max] characters of [text] around the first of [query]'s words.
String snippet(String text, String query, {int max = 280}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= max) return flat;
  final lower = flat.toLowerCase();
  var at = -1;
  for (final m in _words.allMatches(query)) {
    final w = m[0]!.toLowerCase();
    if (w.length < 3 || _stop.contains(w)) continue;
    at = lower.indexOf(w);
    if (at >= 0) break;
  }
  final start = at < 0 ? 0 : math.max(0, at - max ~/ 3);
  final end = math.min(flat.length, start + max);
  return '${start > 0 ? '…' : ''}${flat.substring(start, end).trim()}'
      '${end < flat.length ? '…' : ''}';
}
