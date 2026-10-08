import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/models/attendance.dart';
import 'package:mi_asistencia/src/models/player_tag.dart';
import 'package:mi_asistencia/src/models/team_membership.dart';
import 'package:mi_asistencia/src/screens/session_detail_screen.dart';
import 'package:mi_asistencia/src/theme/app_theme.dart';

TeamMembership _player(String id, String name) {
  return TeamMembership(
    teamId: 'team-1',
    memberId: id,
    fullName: name,
    email: '$id@example.com',
    role: UserRole.player,
    active: true,
  );
}

void main() {
  final members = <TeamRosterMember>[
    _player('ana', 'Ana López'),
    _player('bea', 'Beatriz Ruiz'),
    _player('carla', 'Carla Gómez'),
    _player('dani', 'Daniela Pérez'),
  ];
  final attendance = {
    'ana': const AttendanceRecord(
      userId: 'ana',
      status: AttendanceStatus.attending,
    ),
    'bea': const AttendanceRecord(
      userId: 'bea',
      status: AttendanceStatus.absent,
    ),
    'carla': const AttendanceRecord(
      userId: 'carla',
      status: AttendanceStatus.attending,
    ),
    'dani': const AttendanceRecord(
      userId: 'dani',
      status: AttendanceStatus.attending,
    ),
  };
  const tags = [
    PlayerTag(id: 'gk', name: 'Portero'),
    PlayerTag(id: 'left', name: 'Zurdo'),
    PlayerTag(id: 'empty', name: 'Capitán'),
  ];
  final PlayerTagAssignments assignments = {
    'ana': ['gk', 'left'],
    'bea': ['gk', 'deleted'],
    'carla': ['left'],
    'dani': ['deleted'],
    'former': ['gk'],
  };

  List<String> ids(List<TeamRosterMember> list) =>
      list.map((member) => member.id).toList();

  group('filterSessionMembers', () {
    test('filters by tag only', () {
      final result = filterSessionMembers(
        members: members,
        attendance: attendance,
        tagId: 'gk',
        assignments: assignments,
        tags: tags,
      );
      expect(ids(result), ['ana', 'bea']);
    });

    test('combines tag and status with AND', () {
      final result = filterSessionMembers(
        members: members,
        attendance: attendance,
        status: AttendanceStatus.attending,
        tagId: 'gk',
        assignments: assignments,
        tags: tags,
      );
      expect(ids(result), ['ana']);
    });

    test('combines tag and search query with AND', () {
      final result = filterSessionMembers(
        members: members,
        attendance: attendance,
        tagId: 'left',
        assignments: assignments,
        tags: tags,
        query: 'carla',
      );
      expect(ids(result), ['carla']);
    });

    test('ignores a tag id that no longer exists', () {
      final result = filterSessionMembers(
        members: members,
        attendance: attendance,
        tagId: 'deleted',
        assignments: assignments,
        tags: tags,
      );
      expect(ids(result), ['ana', 'bea', 'carla', 'dani']);
    });

    test('resolveSessionTagFilter clears deleted or empty tags', () {
      final counts = countMembersByTag(
        memberIds: ids(members),
        assignments: assignments,
        tags: tags,
      );
      expect(
        resolveSessionTagFilter(selectedTagId: 'gk', tagCounts: counts),
        'gk',
      );
      expect(
        resolveSessionTagFilter(selectedTagId: 'empty', tagCounts: counts),
        isNull,
      );
      expect(
        resolveSessionTagFilter(selectedTagId: 'deleted', tagCounts: counts),
        isNull,
      );
    });

    test('chip count equals the filtered list length', () {
      final counts = countMembersByTag(
        memberIds: ids(members),
        assignments: assignments,
        tags: tags,
      );
      for (final tag in tags) {
        final result = filterSessionMembers(
          members: members,
          attendance: attendance,
          tagId: tag.id,
          assignments: assignments,
          tags: tags,
        );
        expect(result.length, counts[tag.id], reason: tag.name);
      }
    });
  });

  test('sessionFilterEmptyMessage mentions the tag filter', () {
    expect(
      sessionFilterEmptyMessage(hasStatus: true, hasTag: true, query: ''),
      'Ningún jugador con esta etiqueta tiene este estado de asistencia.',
    );
    expect(
      sessionFilterEmptyMessage(hasStatus: false, hasTag: true, query: 'zz'),
      'Ningún jugador con esta etiqueta coincide con "zz".',
    );
    expect(
      sessionFilterEmptyMessage(hasStatus: true, hasTag: false, query: ''),
      'Ningún jugador tiene este estado de asistencia.',
    );
    expect(
      sessionFilterEmptyMessage(hasStatus: false, hasTag: false, query: 'zz'),
      'Ningún jugador coincide con "zz".',
    );
  });

  group('SessionTagSummary', () {
    Future<void> pumpSummary(
      WidgetTester tester, {
      required Map<String, int> counts,
      Map<String, int> attendingCounts = const {},
      String? selectedTagId,
      ValueChanged<String?>? onTagSelected,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SessionTagSummary(
              tags: tags,
              tagCounts: counts,
              attendingCounts: attendingCounts,
              selectedTagId: selectedTagId,
              onTagSelected: onTagSelected ?? (_) {},
            ),
          ),
        ),
      );
    }

    testWidgets('labels chips as "Name attending/total" and hides zero-count '
        'tags', (tester) async {
      final counts = countMembersByTag(
        memberIds: ids(members),
        assignments: assignments,
        tags: tags,
      );
      await pumpSummary(
        tester,
        counts: counts,
        attendingCounts: {'gk': 1, 'left': 2},
      );

      expect(find.text('Etiquetas'), findsOneWidget);
      expect(find.text('Portero'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('session-tag-count-gk')),
          matching: find.text('1/2'),
        ),
        findsOneWidget,
      );
      expect(find.text('Zurdo'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('session-tag-count-left')),
          matching: find.text('2/2'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('session-tag-chip-gk')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-tag-chip-empty')),
        findsNothing,
      );
      expect(find.textContaining('Capitán'), findsNothing);
    });

    testWidgets('hides the whole section when no tag has players', (
      tester,
    ) async {
      await pumpSummary(tester, counts: {'gk': 0, 'left': 0, 'empty': 0});

      expect(find.text('Etiquetas'), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets('tapping selects a tag and tapping the selected one clears', (
      tester,
    ) async {
      final selections = <String?>[];
      final counts = {'gk': 2, 'left': 2, 'empty': 0};
      await pumpSummary(tester, counts: counts, onTagSelected: selections.add);
      await tester.tap(find.byKey(const ValueKey('session-tag-chip-gk')));

      await pumpSummary(
        tester,
        counts: counts,
        selectedTagId: 'gk',
        onTagSelected: selections.add,
      );
      await tester.tap(find.byKey(const ValueKey('session-tag-chip-gk')));
      await tester.tap(find.byKey(const ValueKey('session-tag-chip-left')));

      expect(selections, ['gk', null, 'left']);
    });
  });
}
