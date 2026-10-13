import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'game_boot.dart';

/// The game: the engine, the first level in assets/scenes/scenes.json, and
/// what its spawn points create.
///
/// Shared by both entry points: lib/main.dart shows it alone, and
/// lib/main_editor.dart boots the same world for the editor.
class GameApp extends StatefulWidget {
  const GameApp({super.key});

  @override
  State<GameApp> createState() => _GameAppState();
}

class _GameAppState extends State<GameApp> {
  Engine? _engine;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final engine = await GameBoot.boot();
    // The level is the JSON the editor saved, loaded through the engine.
    final first = (await SceneLoader.loadManifest()).first;
    await SceneLoader.loadAsset(engine.world, SceneAssets.pathFor(first));
    await LevelMaps.preload(engine.world);
    SpawnPoints.spawnAll(engine.world, GameBoot.spawners);
    engine.start();
    if (!mounted) {
      await engine.dispose();
      return;
    }
    setState(() => _engine = engine);
  }

  @override
  void dispose() {
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine;
    if (engine == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return GameWidget(engine: engine);
  }
}
