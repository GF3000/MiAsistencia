import 'package:cloud_firestore/cloud_firestore.dart';

class TeamSession {
  const TeamSession({
    required this.id,
    required this.teamId,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.recurrenceSeriesId,
  });

  final String id;
  final String teamId;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final String? recurrenceSeriesId;

  TeamSession copyWith({
    String? title,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return TeamSession(
      id: id,
      teamId: teamId,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      recurrenceSeriesId: recurrenceSeriesId,
    );
  }

  factory TeamSession.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return TeamSession(
      id: snapshot.id,
      teamId: data['teamId'] as String? ?? '',
      title: data['title'] as String? ?? 'Entrenamiento',
      startTime: (data['startTime'] as Timestamp).toDate(),
      endTime: (data['endTime'] as Timestamp).toDate(),
      recurrenceSeriesId: data['recurrenceSeriesId'] as String?,
    );
  }
}

class SessionTimelinePosition {
  const SessionTimelinePosition({
    required this.previous,
    required this.next,
    required this.position,
    required this.total,
  });

  final TeamSession? previous;
  final TeamSession? next;
  final int position;
  final int total;
}

SessionTimelinePosition buildSessionTimelinePosition({
  required Iterable<TeamSession> sessions,
  required String currentSessionId,
}) {
  final ordered = sessions.toList()
    ..sort((left, right) {
      final timeComparison = left.startTime.compareTo(right.startTime);
      return timeComparison != 0 ? timeComparison : left.id.compareTo(right.id);
    });
  final index = ordered.indexWhere((session) => session.id == currentSessionId);
  if (index < 0) {
    return const SessionTimelinePosition(
      previous: null,
      next: null,
      position: 1,
      total: 1,
    );
  }
  return SessionTimelinePosition(
    previous: index > 0 ? ordered[index - 1] : null,
    next: index < ordered.length - 1 ? ordered[index + 1] : null,
    position: index + 1,
    total: ordered.length,
  );
}

class SessionOccurrence {
  const SessionOccurrence({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

bool canPlayerEditAttendance(TeamSession session, {DateTime? at}) {
  return session.endTime.isAfter(at ?? DateTime.now());
}

List<TeamSession> sessionsInNextDays(
  Iterable<TeamSession> sessions, {
  required int days,
  DateTime? from,
}) {
  final current = from ?? DateTime.now();
  final start = DateTime(current.year, current.month, current.day);
  final end = start.add(Duration(days: days));
  return sessions
      .where(
        (session) =>
            !session.startTime.isBefore(start) &&
            session.startTime.isBefore(end),
      )
      .toList();
}

List<TeamSession> sessionsOnWeekday(
  Iterable<TeamSession> sessions,
  int weekday,
) {
  return sessions
      .where((session) => session.startTime.weekday == weekday)
      .toList();
}

List<SessionOccurrence> buildSessionOccurrences({
  required DateTime firstDate,
  required DateTime startTime,
  required DateTime endTime,
  required Set<int> weekdays,
  required int weeks,
}) {
  final normalizedDate = DateTime(
    firstDate.year,
    firstDate.month,
    firstDate.day,
  );
  final selectedWeekdays = weekdays.isEmpty
      ? <int>{normalizedDate.weekday}
      : weekdays;
  final occurrences = <SessionOccurrence>[];

  for (var offset = 0; offset < weeks * DateTime.daysPerWeek; offset++) {
    final date = normalizedDate.add(Duration(days: offset));
    if (!selectedWeekdays.contains(date.weekday)) {
      continue;
    }
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      startTime.hour,
      startTime.minute,
    );
    final end = DateTime(
      date.year,
      date.month,
      date.day,
      endTime.hour,
      endTime.minute,
    );
    occurrences.add(SessionOccurrence(start: start, end: end));
  }

  return occurrences;
}
