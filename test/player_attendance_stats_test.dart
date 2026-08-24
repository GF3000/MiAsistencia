import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/models/attendance.dart';
import 'package:mi_asistencia/src/models/team_session.dart';
import 'package:mi_asistencia/src/repositories/attendance_repository.dart';
import 'package:mi_asistencia/src/theme/app_theme.dart';
import 'package:mi_asistencia/src/widgets/player_attendance_table.dart';

void main() {
  test(
    'attendance history emits progress before every session loads',
    () async {
      final session = StreamController<Map<String, AttendanceRecord>>();
      final history = combineAttendanceStreams({'session-1': session.stream});

      final expectation = expectLater(
        history.take(2),
        emitsInOrder([
          isA<AttendanceHistorySnapshot>()
              .having((value) => value.loadedSessionIds.length, 'loaded', 0)
              .having((value) => value.totalSessionCount, 'total', 1),
          isA<AttendanceHistorySnapshot>()
              .having((value) => value.loadedSessionIds, 'loaded', {
                'session-1',
              })
              .having((value) => value.isComplete, 'complete', isTrue),
        ]),
      );

      await Future<void>.delayed(Duration.zero);
      session.add(const <String, AttendanceRecord>{});
      await expectation;
      await session.close();
    },
  );

  test('builds the requested historical player statistics', () {
    const userId = 'player-1';
    final statuses = [
      AttendanceStatus.attending,
      AttendanceStatus.late,
      AttendanceStatus.lateUnannounced,
      AttendanceStatus.gymOnly,
      AttendanceStatus.courtOnly,
      AttendanceStatus.absent,
      AttendanceStatus.absentUnannounced,
      AttendanceStatus.absentLateNotice,
      AttendanceStatus.injured,
    ];
    const player = AppUser(
      id: userId,
      email: 'player@example.com',
      fullName: 'Jugador',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
    );
    final sessions = [
      for (var index = 0; index <= statuses.length; index++)
        TeamSession(
          id: 'session-$index',
          teamId: 'team-1',
          title: 'Sesión $index',
          startTime: DateTime(2026, 8, index + 1, 19),
          endTime: DateTime(2026, 8, index + 1, 20),
        ),
    ];
    final attendanceBySession = {
      for (var index = 0; index < statuses.length; index++)
        'session-$index': {
          userId: AttendanceRecord(userId: userId, status: statuses[index]),
        },
    };

    final stats = buildPlayerAttendanceStats(
      player: player,
      sessions: sessions,
      attendanceBySession: attendanceBySession,
    );

    expect(stats.sessionCount, 10);
    expect(stats.eligibleSessionCount, 9);
    expect(stats.attendedSessionCount, 6);
    expect(stats.attendancePercentage, 67);
    expect(stats.attendanceCount, 2);
    expect(stats.lateCount, 2);
    expect(stats.physicalCount, 5);
    expect(stats.courtCount, 3);
    expect(stats.absenceCount, 3);
    expect(stats.injuryCount, 1);
  });

  testWidgets('renders every requested player statistics column', (
    tester,
  ) async {
    const player = AppUser(
      id: 'player-1',
      email: 'player@example.com',
      fullName: 'Marina García',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
    );
    const stats = PlayerAttendanceStats(
      userId: 'player-1',
      sessionCount: 12,
      eligibleSessionCount: 11,
      attendedSessionCount: 8,
      attendanceCount: 6,
      lateCount: 2,
      physicalCount: 9,
      courtCount: 8,
      absenceCount: 3,
      injuryCount: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: PlayerAttendanceTable(
            loadedSessionCount: 12,
            totalSessionCount: 12,
            rows: [PlayerAttendanceTableRow(player: player, stats: stats)],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('player-attendance-table')),
      findsOneWidget,
    );
    expect(find.text('Marina García'), findsOneWidget);
    expect(find.text('73%'), findsOneWidget);
    for (final heading in [
      'Asistencia %',
      'Sesiones',
      'Asistencias',
      'Retrasos',
      'Físico',
      'Pista',
      'Faltas',
      'Lesiones',
    ]) {
      expect(find.text(heading), findsOneWidget);
    }
  });

  testWidgets('renders partial history without an indefinite spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: PlayerAttendanceTable(
            loadedSessionCount: 1,
            totalSessionCount: 3,
            rows: [],
          ),
        ),
      ),
    );

    expect(find.text('Cargando historial: 1 de 3 sesiones'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('sorts players from every table heading', (tester) async {
    const players = [
      AppUser(
        id: 'ana',
        email: 'ana@example.com',
        fullName: 'Ana',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
      AppUser(
        id: 'bea',
        email: 'bea@example.com',
        fullName: 'Bea',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
      AppUser(
        id: 'carla',
        email: 'carla@example.com',
        fullName: 'Carla',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
    ];
    final rows = [
      PlayerAttendanceTableRow(
        player: players[0],
        stats: PlayerAttendanceStats(
          userId: 'ana',
          sessionCount: 10,
          eligibleSessionCount: 10,
          attendedSessionCount: 5,
          attendanceCount: 4,
          lateCount: 1,
          physicalCount: 6,
          courtCount: 5,
          absenceCount: 5,
          injuryCount: 0,
        ),
      ),
      PlayerAttendanceTableRow(
        player: players[1],
        stats: PlayerAttendanceStats(
          userId: 'bea',
          sessionCount: 9,
          eligibleSessionCount: 8,
          attendedSessionCount: 6,
          attendanceCount: 5,
          lateCount: 1,
          physicalCount: 7,
          courtCount: 6,
          absenceCount: 2,
          injuryCount: 1,
        ),
      ),
      PlayerAttendanceTableRow(
        player: players[2],
        stats: PlayerAttendanceStats(
          userId: 'carla',
          sessionCount: 2,
          eligibleSessionCount: 0,
          attendedSessionCount: 0,
          attendanceCount: 0,
          lateCount: 0,
          physicalCount: 0,
          courtCount: 0,
          absenceCount: 0,
          injuryCount: 2,
        ),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PlayerAttendanceTable(
            loadedSessionCount: 10,
            totalSessionCount: 10,
            rows: rows,
          ),
        ),
      ),
    );

    final table = tester.widget<DataTable>(
      find.byKey(const ValueKey('player-attendance-table')),
    );
    expect(table.columns, hasLength(9));
    expect(table.columns.every((column) => column.onSort != null), isTrue);

    await tester.tap(find.text('Asistencia %'));
    await tester.pump();
    expect(_verticalOrder(tester, ['Ana', 'Bea', 'Carla']), [
      'Ana',
      'Bea',
      'Carla',
    ]);

    await tester.tap(find.text('Asistencia %'));
    await tester.pump();
    expect(_verticalOrder(tester, ['Ana', 'Bea', 'Carla']), [
      'Bea',
      'Ana',
      'Carla',
    ]);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-700, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Faltas'));
    await tester.pump();
    expect(_verticalOrder(tester, ['Ana', 'Bea', 'Carla']), [
      'Carla',
      'Bea',
      'Ana',
    ]);
  });

  testWidgets('downloads either CSV format from the player table', (
    tester,
  ) async {
    const ana = AppUser(
      id: 'ana',
      email: 'ana@example.com',
      fullName: 'Ana',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
    );
    const bea = AppUser(
      id: 'bea',
      email: 'bea@example.com',
      fullName: 'Bea',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
    );
    final session = TeamSession(
      id: 'session-1',
      teamId: 'team-1',
      title: 'Entrenamiento',
      startTime: DateTime(2026, 8, 24, 19),
      endTime: DateTime(2026, 8, 24, 20),
    );
    const anaStats = PlayerAttendanceStats(
      userId: 'ana',
      sessionCount: 10,
      eligibleSessionCount: 10,
      attendedSessionCount: 5,
      attendanceCount: 5,
      lateCount: 0,
      physicalCount: 5,
      courtCount: 5,
      absenceCount: 5,
      injuryCount: 0,
    );
    const beaStats = PlayerAttendanceStats(
      userId: 'bea',
      sessionCount: 8,
      eligibleSessionCount: 8,
      attendedSessionCount: 6,
      attendanceCount: 6,
      lateCount: 0,
      physicalCount: 6,
      courtCount: 6,
      absenceCount: 2,
      injuryCount: 0,
    );
    String? downloadedName;
    String? downloadedContent;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PlayerAttendanceTable(
            loadedSessionCount: 1,
            totalSessionCount: 1,
            rows: const [
              PlayerAttendanceTableRow(player: ana, stats: anaStats),
              PlayerAttendanceTableRow(player: bea, stats: beaStats),
            ],
            completedSessions: [session],
            attendanceBySession: const {
              'session-1': {
                'ana': AttendanceRecord(
                  userId: 'ana',
                  status: AttendanceStatus.absent,
                ),
                'bea': AttendanceRecord(
                  userId: 'bea',
                  status: AttendanceStatus.attending,
                ),
              },
            },
            downloadFile: ({required fileName, required content}) {
              downloadedName = fileName;
              downloadedContent = content;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Asistencia %'));
    await tester.pump();
    await tester.tap(find.text('Asistencia %'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('attendance-csv-menu')));
    await tester.pumpAndSettle();

    expect(find.text('Descargar por jugadores'), findsOneWidget);
    expect(find.text('Descargar por sesión'), findsOneWidget);

    await tester.tap(find.text('Descargar por jugadores'));
    await tester.pumpAndSettle();

    expect(downloadedName, startsWith('asistencia-por-jugadores-'));
    expect(downloadedName, endsWith('.csv'));
    expect(
      downloadedContent!.indexOf('Bea,75%'),
      lessThan(downloadedContent!.indexOf('Ana,50%')),
    );

    await tester.tap(find.byKey(const ValueKey('attendance-csv-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descargar por sesión'));
    await tester.pumpAndSettle();

    expect(downloadedName, startsWith('asistencia-por-sesion-'));
    expect(downloadedName, endsWith('.csv'));
    expect(downloadedContent, contains('Fecha,Sesión,Ana,Bea'));
    expect(
      downloadedContent,
      contains('24/08/2026 19:00,Entrenamiento,No asiste,Asiste'),
    );
  });
}

List<String> _verticalOrder(WidgetTester tester, List<String> labels) {
  final positions = {
    for (final label in labels) label: tester.getTopLeft(find.text(label)).dy,
  };
  return [...labels]
    ..sort((left, right) => positions[left]!.compareTo(positions[right]!));
}
