import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/models/attendance.dart';
import 'package:mi_asistencia/src/models/player_session_history.dart';
import 'package:mi_asistencia/src/models/team_session.dart';

void main() {
  const player = AppUser(
    id: 'player-1',
    email: 'player@example.com',
    fullName: 'Jugador',
    role: UserRole.player,
    teamId: 'team-1',
    active: true,
  );

  test('excludes sessions before the player joined the team', () {
    final earlyPlayer = AppUser(
      id: 'player-1',
      email: 'player@example.com',
      fullName: 'Jugador',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
      teamJoinedAt: DateTime(2026, 8, 10),
    );
    final sessions = [
      TeamSession(
        id: 'before',
        teamId: 'team-1',
        title: 'Antes',
        startTime: DateTime(2026, 8, 1, 19),
        endTime: DateTime(2026, 8, 1, 20),
      ),
      TeamSession(
        id: 'after',
        teamId: 'team-1',
        title: 'Después',
        startTime: DateTime(2026, 8, 20, 19),
        endTime: DateTime(2026, 8, 20, 20),
      ),
    ];

    final history = buildPlayerSessionHistory(
      player: earlyPlayer,
      sessions: sessions,
      attendanceBySession: const {},
    );

    expect(history.entries, hasLength(1));
    expect(history.entries.single.session.id, 'after');
  });

  test('sorts entries most-recent-first', () {
    final sessions = [
      TeamSession(
        id: 'oldest',
        teamId: 'team-1',
        title: 'Sesión 1',
        startTime: DateTime(2026, 8, 1, 19),
        endTime: DateTime(2026, 8, 1, 20),
      ),
      TeamSession(
        id: 'newest',
        teamId: 'team-1',
        title: 'Sesión 2',
        startTime: DateTime(2026, 8, 10, 19),
        endTime: DateTime(2026, 8, 10, 20),
      ),
    ];

    final history = buildPlayerSessionHistory(
      player: player,
      sessions: sessions,
      attendanceBySession: const {},
    );

    expect(
      history.entries.map((entry) => entry.session.id).toList(),
      ['newest', 'oldest'],
    );
  });

  test('collapses unannounced variants into their filter category', () {
    final sessions = [
      for (
        var index = 0;
        index < AttendanceStatus.values.length;
        index++
      )
        TeamSession(
          id: 'session-$index',
          teamId: 'team-1',
          title: 'Sesión $index',
          startTime: DateTime(2026, 8, index + 1, 19),
          endTime: DateTime(2026, 8, index + 1, 20),
        ),
    ];
    final attendanceBySession = {
      for (
        var index = 0;
        index < AttendanceStatus.values.length;
        index++
      )
        'session-$index': {
          player.id: AttendanceRecord(
            userId: player.id,
            status: AttendanceStatus.values[index],
          ),
        },
    };

    final history = buildPlayerSessionHistory(
      player: player,
      sessions: sessions,
      attendanceBySession: attendanceBySession,
    );

    expect(history.counts[PlayerAttendanceFilterCategory.attending], 1);
    expect(history.counts[PlayerAttendanceFilterCategory.late], 2);
    expect(history.counts[PlayerAttendanceFilterCategory.courtOnly], 1);
    expect(history.counts[PlayerAttendanceFilterCategory.gymOnly], 1);
    expect(history.counts[PlayerAttendanceFilterCategory.absent], 3);
    expect(history.counts[PlayerAttendanceFilterCategory.injured], 1);
    // notApplicable is excluded entirely, so total entries = values - 1.
    expect(history.entries, hasLength(AttendanceStatus.values.length - 1));
  });
}
