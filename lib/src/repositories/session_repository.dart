import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/team_session.dart';

class SessionRepository {
  SessionRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<List<TeamSession>> watchSessions(String teamId) {
    return _firestore
        .collection('sessions')
        .where('teamId', isEqualTo: teamId)
        .snapshots()
        .map((snapshot) {
          final sessions = snapshot.docs.map(TeamSession.fromSnapshot).toList();
          sessions.sort(
            (left, right) => left.startTime.compareTo(right.startTime),
          );
          return sessions;
        });
  }

  Future<int> createSessions({
    required String teamId,
    required String title,
    required DateTime firstDate,
    required DateTime startTime,
    required DateTime endTime,
    required Set<int> weekdays,
    required int weeks,
  }) async {
    final occurrences = buildSessionOccurrences(
      firstDate: firstDate,
      startTime: startTime,
      endTime: endTime,
      weekdays: weekdays,
      weeks: weeks,
    );
    if (occurrences.isEmpty) {
      throw ArgumentError('At least one session occurrence is required.');
    }

    final batch = _firestore.batch();
    final seriesId = occurrences.length > 1
        ? _firestore.collection('sessionSeries').doc().id
        : null;
    for (final occurrence in occurrences) {
      final reference = _firestore.collection('sessions').doc();
      batch.set(reference, {
        'teamId': teamId,
        'title': title.trim(),
        'startTime': Timestamp.fromDate(occurrence.start),
        'endTime': Timestamp.fromDate(occurrence.end),
        'recurrenceSeriesId': seriesId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return occurrences.length;
  }

  Future<TeamSession> updateSession({
    required TeamSession session,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    await _firestore.collection('sessions').doc(session.id).update({
      'title': title.trim(),
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
    });
    return session.copyWith(
      title: title.trim(),
      startTime: startTime,
      endTime: endTime,
    );
  }

  Future<void> updateSessions({
    required Iterable<TeamSession> sessions,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final sessionList = sessions.toList();
    for (var offset = 0; offset < sessionList.length; offset += 450) {
      final batch = _firestore.batch();
      final chunk = sessionList.skip(offset).take(450);
      for (final session in chunk) {
        final updates = <String, dynamic>{};
        if (title != null) {
          updates['title'] = title.trim();
        }
        if (startTime != null) {
          updates['startTime'] = Timestamp.fromDate(
            _combineDateAndTime(session.startTime, startTime),
          );
        }
        if (endTime != null) {
          updates['endTime'] = Timestamp.fromDate(
            _combineDateAndTime(session.startTime, endTime),
          );
        }
        batch.update(
          _firestore.collection('sessions').doc(session.id),
          updates,
        );
      }
      await batch.commit();
    }
  }

  Future<void> deleteSessions(Iterable<TeamSession> sessions) async {
    var batch = _firestore.batch();
    var operationCount = 0;

    Future<void> flush() async {
      if (operationCount == 0) {
        return;
      }
      await batch.commit();
      batch = _firestore.batch();
      operationCount = 0;
    }

    for (final session in sessions) {
      final sessionReference = _firestore
          .collection('sessions')
          .doc(session.id);
      final attendance = await sessionReference.collection('attendance').get();
      for (final document in attendance.docs) {
        batch.delete(document.reference);
        operationCount++;
        if (operationCount == 450) {
          await flush();
        }
      }
      batch.delete(sessionReference);
      operationCount++;
      if (operationCount == 450) {
        await flush();
      }
    }
    await flush();
  }

  Future<void> deleteSession(String sessionId) async {
    final sessionReference = _firestore.collection('sessions').doc(sessionId);
    final attendance = await sessionReference.collection('attendance').get();
    final batch = _firestore.batch();
    for (final document in attendance.docs) {
      batch.delete(document.reference);
    }
    batch.delete(sessionReference);
    await batch.commit();
  }

  DateTime _combineDateAndTime(DateTime date, DateTime time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}
