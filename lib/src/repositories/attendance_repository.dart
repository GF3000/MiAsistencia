import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/attendance.dart';

enum AttendanceWriteKind { set, delete }

AttendanceWriteKind planAttendanceWrite({
  required AttendanceStatus status,
  required String note,
  required bool isBatch,
  AttendanceStatus defaultStatus = AttendanceStatus.attending,
}) {
  if (!isBatch && status == defaultStatus && note.trim().isEmpty) {
    return AttendanceWriteKind.delete;
  }
  return AttendanceWriteKind.set;
}

class AttendanceRepository {
  AttendanceRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<AttendanceRecord?> watchAttendance({
    required String sessionId,
    required String userId,
  }) {
    return _attendanceReference(sessionId, userId).snapshots().map(
      (snapshot) =>
          snapshot.exists ? AttendanceRecord.fromSnapshot(snapshot) : null,
    );
  }

  Stream<Map<String, AttendanceRecord>> watchSessionAttendance(
    String sessionId,
  ) {
    return _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('attendance')
        .snapshots()
        .map(
          (snapshot) => {
            for (final document in snapshot.docs)
              document.id: AttendanceRecord.fromSnapshot(document),
          },
        );
  }

  Stream<AttendanceHistorySnapshot> watchAttendanceForSessions(
    Iterable<String> sessionIds,
  ) {
    final ids = sessionIds.toSet().toList(growable: false);
    return combineAttendanceStreams({
      for (final sessionId in ids) sessionId: watchSessionAttendance(sessionId),
    });
  }

  Future<void> saveAttendance({
    required String sessionId,
    required String userId,
    required AttendanceStatus status,
    required String note,
    required String updatedBy,
    AttendanceStatus defaultStatus = AttendanceStatus.attending,
  }) async {
    final reference = _attendanceReference(sessionId, userId);
    if (planAttendanceWrite(
          status: status,
          note: note,
          isBatch: false,
          defaultStatus: defaultStatus,
        ) ==
        AttendanceWriteKind.delete) {
      await reference.delete();
      return;
    }
    await reference.set({
      'status': status.firestoreValue,
      'note': note.trim().isEmpty ? null : note.trim(),
      'updatedBy': updatedBy,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveBatchAttendance({
    required Iterable<String> sessionIds,
    required String userId,
    required AttendanceStatus status,
    required String note,
  }) async {
    final batch = _firestore.batch();
    for (final sessionId in sessionIds) {
      final reference = _attendanceReference(sessionId, userId);
      // An explicit value avoids deleting a missing implicit "Asiste" record,
      // which would make Firestore reject the entire batch.
      batch.set(reference, {
        'status': status.firestoreValue,
        'note': note.trim().isEmpty ? null : note.trim(),
        'updatedBy': userId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  DocumentReference<Map<String, dynamic>> _attendanceReference(
    String sessionId,
    String userId,
  ) {
    return _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('attendance')
        .doc(userId);
  }
}

Stream<AttendanceHistorySnapshot> combineAttendanceStreams(
  Map<String, Stream<Map<String, AttendanceRecord>>> streams, {
  Duration initialLoadTimeout = const Duration(seconds: 15),
}) {
  if (streams.isEmpty) {
    return Stream.value(
      const AttendanceHistorySnapshot(
        attendanceBySession: {},
        loadedSessionIds: {},
        totalSessionCount: 0,
      ),
    );
  }

  late StreamController<AttendanceHistorySnapshot> controller;
  final attendanceBySession = <String, Map<String, AttendanceRecord>>{};
  final loadedSessionIds = <String>{};
  final subscriptions = <StreamSubscription<Map<String, AttendanceRecord>>>[];
  Timer? initialLoadTimer;

  void emit() {
    controller.add(
      AttendanceHistorySnapshot(
        attendanceBySession:
            Map<String, Map<String, AttendanceRecord>>.unmodifiable({
              for (final entry in attendanceBySession.entries)
                entry.key: Map<String, AttendanceRecord>.unmodifiable(
                  entry.value,
                ),
            }),
        loadedSessionIds: Set<String>.unmodifiable(loadedSessionIds),
        totalSessionCount: streams.length,
      ),
    );
  }

  controller = StreamController<AttendanceHistorySnapshot>(
    onListen: () {
      scheduleMicrotask(emit);
      initialLoadTimer = Timer(initialLoadTimeout, () {
        if (loadedSessionIds.length != streams.length) {
          controller.addError(
            TimeoutException(
              'No se pudo cargar todo el historial de asistencias.',
            ),
          );
        }
      });
      for (final entry in streams.entries) {
        subscriptions.add(
          entry.value.listen((attendance) {
            attendanceBySession[entry.key] = attendance;
            loadedSessionIds.add(entry.key);
            if (loadedSessionIds.length == streams.length) {
              initialLoadTimer?.cancel();
            }
            emit();
          }, onError: controller.addError),
        );
      }
    },
    onPause: () {
      for (final subscription in subscriptions) {
        subscription.pause();
      }
    },
    onResume: () {
      for (final subscription in subscriptions) {
        subscription.resume();
      }
    },
    onCancel: () async {
      initialLoadTimer?.cancel();
      await Future.wait(
        subscriptions.map((subscription) => subscription.cancel()),
      );
    },
  );
  return controller.stream;
}
