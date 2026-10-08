import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/player_tag.dart';

PlayerTag tag(String id, String name) => PlayerTag(id: id, name: name);

void main() {
  group('validateTagName', () {
    final existing = [tag('a', 'Portero'), tag('b', 'Zurdo')];

    test('rejects empty and whitespace-only names', () {
      expect(validateTagName(name: '', existing: existing), isNotNull);
      expect(validateTagName(name: '   \t ', existing: existing), isNotNull);
    });

    test('enforces the max length after trimming', () {
      final exact = 'x' * maxTagNameLength;
      expect(maxTagNameLength, 24);
      expect(validateTagName(name: exact, existing: const []), isNull);
      expect(validateTagName(name: '  $exact  ', existing: const []), isNull);
      expect(
        validateTagName(name: 'x' * (maxTagNameLength + 1), existing: const []),
        isNotNull,
      );
    });

    test('accepts a new unique name', () {
      expect(validateTagName(name: 'Defensa', existing: existing), isNull);
    });

    test(
      'rejects duplicates ignoring case, accents and surrounding spaces',
      () {
        expect(validateTagName(name: 'portero', existing: existing), isNotNull);
        expect(
          validateTagName(name: 'pórtero ', existing: existing),
          isNotNull,
        );
        expect(validateTagName(name: ' ZÚRDO', existing: existing), isNotNull);
        expect(
          validateTagName(name: 'Lateral', existing: [tag('c', 'Láteral')]),
          isNotNull,
        );
      },
    );

    test('allows renaming a tag to its own name (any case/accent)', () {
      expect(
        validateTagName(
          name: 'Portero',
          existing: existing,
          renamingTagId: 'a',
        ),
        isNull,
      );
      expect(
        validateTagName(
          name: 'PÓRTERO',
          existing: existing,
          renamingTagId: 'a',
        ),
        isNull,
      );
    });

    test('rejects renaming a tag to another tag\'s name', () {
      expect(
        validateTagName(name: 'zurdo', existing: existing, renamingTagId: 'a'),
        isNotNull,
      );
    });

    test('caps the catalog size on create but not on rename', () {
      final full = [
        for (var i = 0; i < maxTagsPerTeam; i++) tag('t$i', 'Tag $i'),
      ];
      expect(maxTagsPerTeam, 30);
      expect(validateTagName(name: 'Nueva', existing: full), isNotNull);
      expect(validateTagName(name: 'Nueva', existing: full.take(29)), isNull);
      expect(
        validateTagName(name: 'Nueva', existing: full, renamingTagId: 't0'),
        isNull,
      );
    });
  });

  group('sortTags', () {
    test('sorts by name ignoring case and accents', () {
      final sorted = sortTags([
        tag('1', 'zurdo'),
        tag('2', 'Ábside'),
        tag('3', 'banda'),
        tag('4', 'Alto'),
        tag('5', 'Éxito'),
        tag('6', 'delantero'),
      ]);
      expect(sorted.map((t) => t.name).toList(), [
        'Ábside',
        'Alto',
        'banda',
        'delantero',
        'Éxito',
        'zurdo',
      ]);
    });

    test('does not mutate the input', () {
      final input = [tag('1', 'b'), tag('2', 'a')];
      sortTags(input);
      expect(input.map((t) => t.id).toList(), ['1', '2']);
    });
  });

  group('tagIdsFor', () {
    final catalog = [tag('a', 'A'), tag('b', 'B'), tag('c', 'C')];

    test('drops deleted ids and follows catalog order', () {
      final ids = tagIdsFor(
        memberId: 'm1',
        assignments: {
          'm1': ['c', 'gone', 'a'],
        },
        tags: catalog,
      );
      expect(ids, ['a', 'c']);
    });

    test('returns empty for a member without assignment', () {
      expect(
        tagIdsFor(memberId: 'missing', assignments: {}, tags: catalog),
        isEmpty,
      );
    });

    test('collapses duplicate ids', () {
      expect(
        tagIdsFor(
          memberId: 'm1',
          assignments: {
            'm1': ['b', 'b'],
          },
          tags: catalog,
        ),
        ['b'],
      );
    });
  });

  group('countMembersByTag', () {
    final catalog = [tag('a', 'A'), tag('b', 'B'), tag('c', 'C')];

    test('counts listed members only, once per tag, ignoring unknown ids', () {
      final counts = countMembersByTag(
        memberIds: ['m1', 'm2', 'm4'],
        assignments: {
          'm1': ['a', 'a', 'b'],
          'm2': ['a', 'unknown'],
          'm3': ['a', 'b', 'c'], // not listed
        },
        tags: catalog,
      );
      expect(counts, {'a': 2, 'b': 1, 'c': 0});
    });

    test('includes zero-count tags when nobody has tags', () {
      expect(
        countMembersByTag(memberIds: ['m1'], assignments: {}, tags: catalog),
        {'a': 0, 'b': 0, 'c': 0},
      );
    });

    test('empty catalog yields empty map', () {
      expect(
        countMembersByTag(
          memberIds: ['m1'],
          assignments: {
            'm1': ['a'],
          },
          tags: const [],
        ),
        isEmpty,
      );
    });
  });

  group('parseTagIds', () {
    test('handles null data and missing field', () {
      expect(parseTagIds(null), isEmpty);
      expect(parseTagIds(<String, dynamic>{}), isEmpty);
    });

    test('filters non-string entries', () {
      expect(
        parseTagIds({
          'tagIds': ['a', 1, null, 'b', true],
        }),
        ['a', 'b'],
      );
    });
  });

  group('isAtTagLimitFor', () {
    final tags = [
      for (var i = 0; i < 6; i++) PlayerTag(id: 't$i', name: 'Tag $i'),
    ];
    final assignments = <String, List<String>>{
      'full': ['t0', 't1', 't2', 't3', 't4'],
      'withDeleted': ['t0', 't1', 't2', 't3', 'gone'],
    };

    test('a player with 5 other tags is at the limit', () {
      expect(
        isAtTagLimitFor(
          memberId: 'full',
          tagId: 't5',
          assignments: assignments,
          tags: tags,
        ),
        isTrue,
      );
    });

    test('a player that already carries the tag is not blocked', () {
      expect(
        isAtTagLimitFor(
          memberId: 'full',
          tagId: 't0',
          assignments: assignments,
          tags: tags,
        ),
        isFalse,
      );
    });

    test('deleted tags and missing players do not count', () {
      expect(
        isAtTagLimitFor(
          memberId: 'withDeleted',
          tagId: 't5',
          assignments: assignments,
          tags: tags,
        ),
        isFalse,
      );
      expect(
        isAtTagLimitFor(
          memberId: 'nobody',
          tagId: 't5',
          assignments: assignments,
          tags: tags,
        ),
        isFalse,
      );
    });
  });
}
