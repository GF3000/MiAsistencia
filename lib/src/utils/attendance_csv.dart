import '../models/attendance.dart';
import '../models/team_membership.dart';
import '../models/team_session.dart';

typedef PlayerAttendanceCsvRow = ({
  String playerName,
  PlayerAttendanceStats stats,
});

String buildPlayerAttendanceCsv(Iterable<PlayerAttendanceCsvRow> rows) {
  return _encodeCsv([
    const [
      'Jugador',
      'Asistencia %',
      'Sesiones',
      'Asistencias',
      'Retrasos',
      'Físico',
      'Pista',
      'Faltas',
      'Lesiones',
    ],
    for (final row in rows)
      [
        row.playerName,
        row.stats.attendancePercentage == null
            ? '—'
            : '${row.stats.attendancePercentage}%',
        row.stats.sessionCount,
        row.stats.attendanceCount,
        row.stats.lateCount,
        row.stats.physicalCount,
        row.stats.courtCount,
        row.stats.absenceCount,
        row.stats.injuryCount,
      ],
  ]);
}

String buildSessionAttendanceCsv({
  required Iterable<TeamRosterMember> players,
  required Iterable<TeamSession> sessions,
  required Map<String, Map<String, AttendanceRecord>> attendanceBySession,
}) {
  final orderedPlayers = players.toList()
    ..sort(
      (left, right) =>
          left.fullName.toLowerCase().compareTo(right.fullName.toLowerCase()),
    );
  final orderedSessions = sessions.toList()
    ..sort((left, right) {
      final timeComparison = left.startTime.compareTo(right.startTime);
      return timeComparison != 0 ? timeComparison : left.id.compareTo(right.id);
    });

  return _encodeCsv([
    ['Fecha', 'Sesión', ...orderedPlayers.map((player) => player.fullName)],
    for (final session in orderedSessions)
      [
        _formatDateTime(session.startTime),
        session.title,
        for (final player in orderedPlayers)
          resolveAttendanceStatus(
            user: player,
            explicitRecord: attendanceBySession[session.id]?[player.id],
            sessionTime: session.startTime,
          ).coachLabel,
      ],
  ]);
}

String _encodeCsv(Iterable<Iterable<Object?>> rows) {
  final content = rows
      .map((row) => row.map(_encodeCell).join(','))
      .join('\r\n');
  return '\uFEFF$content\r\n';
}

String _encodeCell(Object? value) {
  var text = value?.toString() ?? '';
  if (RegExp(r'^\s*[=+\-@]').hasMatch(text)) {
    text = "'$text";
  }
  if (text.contains(',') ||
      text.contains('"') ||
      text.contains('\r') ||
      text.contains('\n')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

String _formatDateTime(DateTime value) {
  String twoDigits(int part) => part.toString().padLeft(2, '0');
  return '${twoDigits(value.day)}/${twoDigits(value.month)}/${value.year} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}
