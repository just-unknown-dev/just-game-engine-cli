/// The engine's packages, at versions that work together.
library;

import 'package:just_core_cli/just_core_cli.dart';

/// The Just Game Engine's packages, at versions that work together, and the
/// Flutter and Dart they need: what `just game init` starts a game on,
/// what `just game doctor` checks it against, and what `just game upgrade`
/// (the `upgrade` hook of `just upgrade`) moves it to.
///
/// Each just_game_engine_cli release carries its own set, so the engine's
/// versions travel with the commands that know them. The tools —
/// just_core_cli and this package — are just_core_cli's [ToolSet].
final class GameSet extends PackageSet {
  /// The set [id], for [flutter] and [dart], holding [packages]; new games
  /// are pinned to Flutter [flutterPin].
  const GameSet({
    required super.id,
    required this.flutter,
    required this.dart,
    required super.packages,
    this.flutterPin,
  });

  /// The set this version of just_game_engine_cli is made for.
  ///
  /// Its id names the month it was made, as just_core_cli's [ToolSet] does:
  /// both are 2026.11 for just_core_cli 0.2.0 and just_game_engine_cli
  /// 0.2.0. A constraint on a prerelease names that prerelease
  /// (`^0.2.0-beta.1`, as the kits below): a caret on a release leaves its
  /// prereleases out.
  static const GameSet current = GameSet(
    id: '2026.11',
    // just_game_engine draws 3D with just_graphics_engine, which needs
    // Flutter GPU as it is from 3.47.1 (Dart 3.12.2). Flutter GPU is a
    // preview: its API may change in the next minor, so 3.48 is out until
    // the engine is tried on it.
    flutter: '>=3.47.1 <3.48.0',
    dart: '^3.12.2',
    // The exact Flutter each new game is pinned to ("flutter" in its
    // just.json), and `just upgrade` moves games to. The same version is
    // in this package's pubspec (`just: flutter:`), where just_core_cli
    // reads it before the package is fetched; a test keeps the two equal.
    flutterPin: '3.47.9',
    packages: [
      SetPackage('just_game_engine', '^2.0.0'),
      SetPackage('just_game_engine_formats', '^0.3.0'),
      SetPackage('just_physics_engine', '^2.0.0'),
      // Box2D for the physics engine's 2D, built by default; a game
      // turns it off with hooks: user_defines: just_box_2d: build: false.
      SetPackage('just_box_2d', '^0.2.0'),
      // Jolt for the physics engine's 3D. Every game has it through
      // just_physics_engine; only a 3D game's pubspec builds it
      // (hooks: user_defines: just_jolt: build: true).
      SetPackage('just_jolt', '^0.2.0'),
      SetPackage('just_inputs', '^0.2.0'),
      SetPackage('just_tiled', '^0.5.0'),
      SetPackage('just_dart', '^0.3.0'),
      // The engine's 3D graphics (Graphics3D). Every game has it through
      // just_game_engine; a 2D game never makes a GPU device.
      SetPackage('just_graphics_engine', '^0.2.0'),
      SetPackage('just_deflate', '^0.1.0'),
      SetPackage('just_audio_engine', '^2.0.0'),
      // The Asset Store: a tool, never shipped. From pub.dev, where
      // just_core_cli trusts it (PluginTrust.onPubDev, from 0.1.1).
      SetPackage('just_asset_store', '^0.3.0', dev: true),
      // The editor, with the Asset Store's window built in: plugins and
      // kits are added from inside it. From pub.dev, like every
      // package; only plugins (the kits and editor tools below) come from
      // the store.
      SetPackage('just_game_engine_editor', '^0.1.0', dev: true),
      // What the editor and every kit's editor side build on: it comes
      // with them, never on its own.
      SetPackage('just_editor_core', '^0.1.0'),
      // The 3D kits, for games that use them (the third-person template).
      // A new 2D game doesn't get them. Editing 3D graphics is the editor's
      // own.
      SetPackage(
        'just_world_builder_kit',
        '^0.2.0-beta.1',
        source: PackageSource.plugin,
      ),
      SetPackage(
        'just_third_person_kit',
        '^0.2.0-beta.1',
        source: PackageSource.plugin,
      ),
    ],
  );

  /// The sets this version knows, oldest first.
  static const List<GameSet> known = [current];

  /// The set called [id], or null when this version doesn't know it.
  static GameSet? named(String id) {
    for (final s in known) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The Flutter versions it works with: a range, for `just game doctor`
  /// to check a game's Flutter against.
  final String flutter;

  /// The one Flutter version games on this set are pinned to, exactly:
  /// what `just sdk install` installs for them. Null: none pinned.
  final String? flutterPin;

  /// The Dart SDK constraint games get.
  final String dart;

  /// [pubspec] with each of this set's packages it names on one line moved
  /// to the set's constraint, and what moved: name → `{from, to}`.
  ///
  /// A game ahead of the set is never moved back: a package stays as it is
  /// when its constraint's lowest version is the set's or newer, or when
  /// pub resolved it ([resolved]: name → version) past the set. Entries
  /// written as blocks (a git source, a path) stay too
  /// ([PubspecConstraints]).
  ///
  /// The game's own Flutter range (`environment: flutter:`, which pub
  /// enforces for the game) moves to [flutter] too, either way: it goes
  /// with the Flutter the set pins. Listed as [flutterKey].
  (String, Map<String, Map<String, String>>) bump(
    String pubspec, {
    Map<String, Version> resolved = const {},
  }) {
    var next = pubspec;
    final bumps = <String, Map<String, String>>{};
    for (final p in packages) {
      final floor = p.versions.min;
      if (resolved[p.name] case final v?
          when floor != null && v > floor && !p.versions.allows(v)) {
        continue;
      }
      for (final section in const ['dependencies', 'dev_dependencies']) {
        final now = PubspecConstraints.of(next, section, p.name);
        if (now == null || now == p.constraint) continue;
        final from = VersionConstraint.tryParse(now)?.min;
        if (from != null && floor != null && from >= floor) continue;
        next = PubspecConstraints.set(next, section, p.name, p.constraint);
        bumps[p.name] = {'from': now, 'to': p.constraint};
      }
    }
    final range = PubspecConstraints.of(next, 'environment', 'flutter');
    if (range != null && range != flutter) {
      next = PubspecConstraints.set(next, 'environment', 'flutter', flutter);
      bumps[flutterKey] = {'from': range, 'to': flutter};
    }
    return (next, bumps);
  }

  /// How [bump] lists the game's Flutter range among what moved.
  static const flutterKey = 'environment: flutter';

  /// The packages only a link to a checkout can supply when [pubspec] asks
  /// pub.dev for them by version: those of [names] this set gets from git
  /// or the Asset Store, which pub.dev doesn't have.
  List<String> linkOnly(String pubspec, Iterable<String> names) => [
    for (final name in names)
      if (this[name] case final p?
          when p.source != PackageSource.hosted &&
              const [
                'dependencies',
                'dev_dependencies',
              ].any((s) => PubspecConstraints.of(pubspec, s, name) != null))
        name,
  ]..sort();
}
