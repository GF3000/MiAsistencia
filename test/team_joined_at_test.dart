import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/models/attendance.dart';
import 'package:mi_asistencia/src/models/player_motivation.dart';
import 'package:mi_asistencia/src/models/team_session.dart';
import 'package:mi_asistencia/src/screens/session_detail_screen.dart';

void main() {
  const player = AppUser(
    id: 'player',
    email: 'player@example.com',
    fullName: 'Jugador nuevo',
    role: UserRole.player,
    teamId: 'team-1',
    active: true,
    teamJoinedAt: null,
  );

  test('pre-membership sessions default to not applicable', () {
    final joinedPlayer = AppUser(
      id: player.id,
      email: player.email,
      fullName: player.fullName,
      role: player.role,
      teamId: player.teamId,
      active: player.active,
      teamJoinedAt: DateTime(2026, 8, 10),
    );

    expect(
      resolveAttendanceStatus(
        user: joinedPlayer,
        explicitRecord: null,
        sessionTime: DateTime(2026, 8, 9, 19),
      ),
      AttendanceStatus.notApplicable,
    );
    expect(
      resolveAttendanceStatus(
        user: joinedPlayer,
        explicitRecord: null,
        sessionTime: DateTime(2026, 8, 10, 19),
      ),
      AttendanceStatus.attending,
    );

    final legacyPlayer = AppUser(
      id: player.id,
      email: player.email,
      fullName: player.fullName,
      role: player.role,
      teamId: player.teamId,
      active: player.active,
      createdAt: DateTime(2026, 8, 10),
    );
    expect(
      resolveAttendanceStatus(
        user: legacyPlayer,
        explicitRecord: null,
        sessionTime: DateTime(2026, 8, 9, 19),
      ),
      AttendanceStatus.notApplicable,
    );
  });

  test('an explicit coach override wins before the membership date', () {
    final joinedPlayer = AppUser(
      id: player.id,
      email: player.email,
      fullName: player.fullName,
      role: player.role,
      teamId: player.teamId,
      active: player.active,
      teamJoinedAt: DateTime(2026, 8, 10),
    );
    const override = AttendanceRecord(
      userId: 'player',
      status: AttendanceStatus.absentUnannounced,
    );

    expect(
      resolveAttendanceStatus(
        user: joinedPlayer,
        explicitRecord: override,
        sessionTime: DateTime(2026, 8, 9, 19),
      ),
      AttendanceStatus.absentUnannounced,
    );
  });

  test('pre-membership sessions are excluded from statistics and KPIs', () {
    final joinedPlayer = AppUser(
      id: player.id,
      email: player.email,
      fullName: player.fullName,
      role: player.role,
      teamId: player.teamId,
      active: player.active,
      teamJoinedAt: DateTime(2026, 8, 10),
    );
    final sessions = [
      TeamSession(
        id: 'before',
        teamId: 'team-1',
        title: 'Antes',
        startTime: DateTime(2026, 8, 9, 19),
        endTime: DateTime(2026, 8, 9, 20),
      ),
      TeamSession(
        id: 'after',
        teamId: 'team-1',
        title: 'Después',
        startTime: DateTime(2026, 8, 11, 19),
        endTime: DateTime(2026, 8, 11, 20),
      ),
    ];

    final stats = buildPlayerAttendanceStats(
      player: joinedPlayer,
      sessions: sessions,
      attendanceBySession: const {},
    );
    final kpis = buildPlayerMotivationKpis(
      currentPlayer: joinedPlayer,
      members: [joinedPlayer],
      completedSessions: sessions,
      attendanceBySession: const {},
      referenceDate: DateTime(2026, 8, 24),
    );

    expect(stats.sessionCount, 1);
    expect(stats.attendanceCount, 1);
    expect(kpis.recentEligibleSessionCount, 1);
    expect(kpis.recentAttendancePercentage, 100);
    expect(kpis.attendanceStreak, 1);
  });

  testWidgets('coach roster renders a dash for pre-membership sessions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoachAttendanceListItem(
            member: player,
            record: const AttendanceRecord(
              userId: 'player',
              status: AttendanceStatus.notApplicable,
            ),
            updateLabel: 'Se unió después de esta sesión',
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('—'), findsOneWidget);
    expect(find.text('Se unió después de esta sesión'), findsOneWidget);
  });
}
