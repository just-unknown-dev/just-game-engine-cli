// `just game mcp`'s search.

@TestOn('vm')
library;

import 'package:just_game_engine_cli/src/mcp/search_index.dart';
import 'package:test/test.dart';

void main() {
  group('search', () {
    test('splits names and finds them whole', () {
      expect(tokens('CharacterBody2DComponent moves'), [
        'characterbody2dcomponent',
        'character',
        'body',
        '2d',
        'component',
        'move',
      ]);
      final index = SearchIndex([
        const SearchEntry(
          kind: 'api',
          title: 'CharacterBody2DComponent',
          text: 'class CharacterBody2DComponent A character the game moves.',
          ref: {'symbol': 'CharacterBody2DComponent'},
        ),
        const SearchEntry(
          kind: 'guide',
          title: '2D physics › Bodies',
          text: 'Rigid bodies fall; a body is pushed by forces.',
          ref: {'doc': 'physics-2d'},
        ),
      ]);
      expect(
        index.search('CharacterBody2DComponent').first.entry.title,
        'CharacterBody2DComponent',
      );
      expect(index.search('rigid body forces').first.entry.kind, 'guide');
      expect(index.search('body', kinds: {'api'}).single.entry.kind, 'api');
      expect(index.search('the of'), isEmpty);
    });
  });
}
