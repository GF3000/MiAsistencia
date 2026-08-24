import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/models/attendance.dart';
import 'package:mi_asistencia/src/models/team_session.dart';
import 'package:mi_asistencia/src/utils/attendance_csv.dart';

void main() {
  test('exports the player table format and escapes spreadsheet input', () {
    const stats = PlayerAttendanceStats(
      userId: 'player-1',
      sessionCount: 10,
      eligibleSessionCount: 8,
      attendedSessionCount: 6,
      attendanceCount: 4,
      lateCount: 2,
      physicalCount: 7,
      courtCount: 6,
      absenceCount: 2,
      injuryCount: 2,
    );

    final csv = buildPlayerAttendanceCsv([
      (playerName: 'García, Ana', stats: stats),
      (playerName: '=2+2', stats: stats),
    ]);

    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(
      csv,
      contains(
        'Jugador,Asistencia %,Sesiones,Asistencias,Retrasos,Físico,Pista,'
        'Faltas,Lesiones\r\n',
      ),
    );
    expect(csv, contains('"García, Ana",75%,10,4,2,7,6,2,2\r\n'));
    expect(csv, contains("'=2+2,75%,10,4,2,7,6,2,2\r\n"));
  });

  test('exports sessions chronologically with players as columns', () {
    final sessions = [
      TeamSession(
        id: 'later',
        teamId: 'team-1',
        title: 'Entreno, tarde',
        startTime: DateTime(2026, 8, 24, 19, 5),
        endTime: DateTime(2026, 8, 24, 20, 5),
      ),
      TeamSession(
        id: 'earlier',
        teamId: 'team-1',
        title: '=Sesión inicial',
        startTime: DateTime(2026, 8, 20, 9, 0),
        endTime: DateTime(2026, 8, 20, 10, 0),
      ),
    ];
    final players = [
      AppUser(
        id: 'bea',
        email: 'bea@example.com',
        fullName: 'Bea',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
        teamJoinedAt: DateTime(2026, 8, 22),
      ),
      const AppUser(
        id: 'ana',
        email: 'ana@example.com',
        fullName: 'Ana',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
    ];
    final attendance = {
      'earlier': {
        'ana': const AttendanceRecord(
          userId: 'ana',
          status: AttendanceStatus.absentUnannounced,
        ),
      },
      'later': {
        'ana': const AttendanceRecord(
          userId: 'ana',
          status: AttendanceStatus.late,
        ),
        'bea': const AttendanceRecord(
          userId: 'bea',
          status: AttendanceStatus.courtOnly,
        ),
      },
    };

    final csv = buildSessionAttendanceCsv(
      players: players,
      sessions: sessions,
      attendanceBySession: attendance,
    );

    expect(csv, contains('Fecha,Sesión,Ana,Bea\r\n'));
    final earlier = csv.indexOf(
      "20/08/2026 09:00,'=Sesión inicial,Falta sin avisar,—",
    );
    final later = csv.indexOf(
      '24/08/2026 19:05,"Entreno, tarde",Llega tarde,Solo pista',
    );
    expect(earlier, greaterThanOrEqualTo(0));
    expect(later, greaterThan(earlier));
  });
}
