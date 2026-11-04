import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/models/attendance.dart';
import 'package:mi_asistencia/src/models/team_session.dart';
import 'package:mi_asistencia/src/widgets/app_widgets.dart';

const _player = AppUser(
  id: 'player-1',
  email: 'player@example.com',
  fullName: 'Jugador',
  role: UserRole.player,
  teamId: 'team-1',
  active: true,
);

TeamSession _session(int day, {SessionKind kind = SessionKind.training}) {
  return TeamSession(
    id: 'session-$day',
    teamId: 'team-1',
    title: kind.label,
    startTime: DateTime(2026, 9, day, 19),
    endTime: DateTime(2026, 9, day, 20),
    kind: kind,
  );
}

AttendanceRecord _record(AttendanceStatus status) =>
    AttendanceRecord(userId: _player.id, status: status);

void main() {
  test('sessions without a kind are trainings', () {
    expect(SessionKind.fromFirestore(null), SessionKind.training);
    expect(SessionKind.fromFirestore('training'), SessionKind.training);
    expect(SessionKind.fromFirestore('match'), SessionKind.match);
  });

  test('matches offer their own statuses and labels', () {
    expect(AttendanceStatus.playerOptionsFor(SessionKind.match), [
      AttendanceStatus.attending,
      AttendanceStatus.injured,
      AttendanceStatus.absent,
    ]);
    expect(AttendanceStatus.coachOnlyOptionsFor(SessionKind.match), [
      AttendanceStatus.noConvocado,
      AttendanceStatus.absentUnannounced,
    ]);
    // No convocado locks the player out of changing their status.
    expect(AttendanceStatus.noConvocado.isCoachOnly, isTrue);
    expect(
      AttendanceStatus.attending.labelIn(
        SessionKind.match,
        AttendanceLabelPerspective.player,
      ),
      'Asisto',
    );
    expect(
      AttendanceStatus.attending.labelIn(
        SessionKind.match,
        AttendanceLabelPerspective.coach,
      ),
      'Asiste',
    );
    expect(
      AttendanceStatus.absent.labelIn(
        SessionKind.match,
        AttendanceLabelPerspective.coach,
      ),
      'No disponible',
    );
    expect(
      AttendanceStatus.absent.labelIn(
        SessionKind.match,
        AttendanceLabelPerspective.player,
      ),
      'No disponible',
    );
    expect(
      AttendanceStatus.attending.labelIn(
        SessionKind.training,
        AttendanceLabelPerspective.player,
      ),
      'Asisto',
    );
  });

  test('training statuses left on a session turned into a match collapse', () {
    for (final status in [
      AttendanceStatus.courtOnly,
      AttendanceStatus.gymOnly,
      AttendanceStatus.late,
      AttendanceStatus.lateUnannounced,
    ]) {
      expect(status.inKind(SessionKind.match), AttendanceStatus.attending);
      expect(status.attendsIn(SessionKind.match), isTrue);
    }
    expect(
      AttendanceStatus.absentLateNotice.inKind(SessionKind.match),
      AttendanceStatus.absent,
    );
    expect(
      AttendanceStatus.gymOnly.inKind(SessionKind.training),
      AttendanceStatus.gymOnly,
    );
  });

  test('matches stay out of training stats and are counted apart', () {
    final sessions = [
      _session(1),
      _session(2),
      _session(3, kind: SessionKind.match),
      _session(4, kind: SessionKind.match),
      _session(5, kind: SessionKind.match),
      _session(6, kind: SessionKind.match),
      _session(7, kind: SessionKind.match),
    ];
    final stats = buildPlayerAttendanceStats(
      player: _player,
      sessions: sessions,
      attendanceBySession: {
        'session-2': {_player.id: _record(AttendanceStatus.absent)},
        // Presumed called up (session-3) and an old training status
        // (session-4) both count as matches played.
        'session-4': {_player.id: _record(AttendanceStatus.courtOnly)},
        'session-5': {_player.id: _record(AttendanceStatus.noConvocado)},
        'session-6': {_player.id: _record(AttendanceStatus.injured)},
        'session-7': {_player.id: _record(AttendanceStatus.absent)},
      },
      now: DateTime(2026, 10, 1),
    );

    expect(stats.sessionCount, 2);
    expect(stats.attendancePercentage, 50);
    expect(stats.courtCount, 1);
    expect(stats.absenceCount, 1);
    expect(stats.injuryCount, 0);
    expect(stats.matchCount, 2);
    expect(stats.uncalledMatchCount, 1);
  });

  test('match roster splits called-up and available players', () {
    final summary = buildMatchRosterSummary(
      members: [
        _player,
        const AppUser(
          id: 'player-2',
          email: 'p2@example.com',
          fullName: 'Dos',
          role: UserRole.player,
          teamId: 'team-1',
          active: true,
        ),
        const AppUser(
          id: 'player-3',
          email: 'p3@example.com',
          fullName: 'Tres',
          role: UserRole.player,
          teamId: 'team-1',
          active: true,
        ),
        const AppUser(
          id: 'player-4',
          email: 'p4@example.com',
          fullName: 'Cuatro',
          role: UserRole.player,
          teamId: 'team-1',
          active: true,
        ),
      ],
      attendance: {
        'player-2': const AttendanceRecord(
          userId: 'player-2',
          status: AttendanceStatus.absent,
        ),
        'player-3': const AttendanceRecord(
          userId: 'player-3',
          status: AttendanceStatus.noConvocado,
        ),
        'player-4': const AttendanceRecord(
          userId: 'player-4',
          status: AttendanceStatus.injured,
        ),
      },
      sessionTime: DateTime(2026, 9, 1, 19),
    );

    // Everyone but player 3 (no convocado) is called up; of them only
    // player 1 (presumed) attends.
    expect(summary.attending.label, '1/3');
    expect(summary.uncalled, 1);
  });

  testWidgets('attendance badge uses match labels', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AttendanceBadge(
                status: AttendanceStatus.late,
                perspective: AttendanceLabelPerspective.coach,
                kind: SessionKind.match,
              ),
              AttendanceBadge(
                status: AttendanceStatus.late,
                perspective: AttendanceLabelPerspective.player,
                kind: SessionKind.match,
              ),
            ],
          ),
        ),
      ),
    );

    // Late arrivals left on a session turned into a match read as attending.
    expect(find.text('Asiste'), findsOneWidget);
    expect(find.text('Asisto'), findsOneWidget);
  });

  testWidgets('kind selector reports the chosen kind', (tester) async {
    SessionKind? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionKindSelector(
            value: SessionKind.training,
            onChanged: (kind) => chosen = kind,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Partido'));
    await tester.pump();

    expect(chosen, SessionKind.match);
  });
}
