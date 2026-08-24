import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_user.dart';
import 'team_session.dart';

enum AttendanceLabelPerspective { player, coach }

enum AttendanceStatus {
  attending,
  injured,
  courtOnly,
  gymOnly,
  late,
  absent,
  lateUnannounced,
  absentUnannounced,
  absentLateNotice,
  notApplicable;

  String get firestoreValue => switch (this) {
    AttendanceStatus.attending => 'attending',
    AttendanceStatus.injured => 'injured',
    AttendanceStatus.courtOnly => 'court_only',
    AttendanceStatus.gymOnly => 'gym_only',
    AttendanceStatus.late => 'late',
    AttendanceStatus.absent => 'absent',
    AttendanceStatus.lateUnannounced => 'late_unannounced',
    AttendanceStatus.absentUnannounced => 'absent_unannounced',
    AttendanceStatus.absentLateNotice => 'absent_late_notice',
    AttendanceStatus.notApplicable => throw StateError(
      'notApplicable cannot be stored in Firestore.',
    ),
  };

  String labelFor(AttendanceLabelPerspective perspective) {
    return perspective == AttendanceLabelPerspective.player
        ? playerLabel
        : coachLabel;
  }

  String get playerLabel => switch (this) {
    AttendanceStatus.attending => 'Asisto',
    AttendanceStatus.injured => 'Lesión',
    AttendanceStatus.courtOnly => 'Solo pista',
    AttendanceStatus.gymOnly => 'Solo físico',
    AttendanceStatus.late => 'Llego tarde',
    AttendanceStatus.absent => 'No asisto',
    AttendanceStatus.lateUnannounced => 'Llegué tarde sin avisar',
    AttendanceStatus.absentUnannounced => 'Falté sin avisar',
    AttendanceStatus.absentLateNotice => 'Avisé tarde de que no iba',
    AttendanceStatus.notApplicable => '—',
  };

  String get coachLabel => switch (this) {
    AttendanceStatus.attending => 'Asiste',
    AttendanceStatus.injured => 'Lesionado',
    AttendanceStatus.courtOnly => 'Solo pista',
    AttendanceStatus.gymOnly => 'Solo físico',
    AttendanceStatus.late => 'Llega tarde',
    AttendanceStatus.absent => 'No asiste',
    AttendanceStatus.lateUnannounced => 'Llega tarde sin avisar',
    AttendanceStatus.absentUnannounced => 'Falta sin avisar',
    AttendanceStatus.absentLateNotice => 'Avisa tarde de que no viene',
    AttendanceStatus.notApplicable => '—',
  };

  IconData get icon => switch (this) {
    AttendanceStatus.attending => Icons.check_circle_outline,
    AttendanceStatus.injured => Icons.healing_outlined,
    AttendanceStatus.courtOnly => Icons.sports_basketball_outlined,
    AttendanceStatus.gymOnly => Icons.fitness_center_outlined,
    AttendanceStatus.late => Icons.schedule_outlined,
    AttendanceStatus.absent => Icons.cancel_outlined,
    AttendanceStatus.lateUnannounced => Icons.timer_off_outlined,
    AttendanceStatus.absentUnannounced => Icons.person_off_outlined,
    AttendanceStatus.absentLateNotice => Icons.notification_important_outlined,
    AttendanceStatus.notApplicable => Icons.remove_circle_outline,
  };

  Color get color => switch (this) {
    AttendanceStatus.attending => const Color(0xFF1B7F5C),
    AttendanceStatus.injured => const Color(0xFFC2413B),
    AttendanceStatus.courtOnly => const Color(0xFF2563A5),
    AttendanceStatus.gymOnly => const Color(0xFF7650A8),
    AttendanceStatus.late => const Color(0xFFB76505),
    AttendanceStatus.absent => const Color(0xFF5C6670),
    AttendanceStatus.lateUnannounced => const Color(0xFFB45309),
    AttendanceStatus.absentUnannounced => const Color(0xFFB42318),
    AttendanceStatus.absentLateNotice => const Color(0xFF9A3412),
    AttendanceStatus.notApplicable => const Color(0xFF7A8793),
  };

  bool get countsAsAttending =>
      this == AttendanceStatus.attending ||
      this == AttendanceStatus.courtOnly ||
      this == AttendanceStatus.late ||
      this == AttendanceStatus.lateUnannounced;

  bool get countsForAttendancePercentage =>
      this == AttendanceStatus.attending ||
      this == AttendanceStatus.late ||
      this == AttendanceStatus.lateUnannounced ||
      this == AttendanceStatus.courtOnly ||
      this == AttendanceStatus.gymOnly;

  bool get isAttendancePercentageEligible =>
      this != AttendanceStatus.injured &&
      this != AttendanceStatus.notApplicable;

  bool get isCoachOnly =>
      this == AttendanceStatus.lateUnannounced ||
      this == AttendanceStatus.absentUnannounced ||
      this == AttendanceStatus.absentLateNotice;

  AttendanceStatus get playerEquivalent => switch (this) {
    AttendanceStatus.lateUnannounced => AttendanceStatus.late,
    AttendanceStatus.absentUnannounced ||
    AttendanceStatus.absentLateNotice => AttendanceStatus.absent,
    _ => this,
  };

  static List<AttendanceStatus> get playerOptions => values
      .where(
        (status) =>
            !status.isCoachOnly && status != AttendanceStatus.notApplicable,
      )
      .toList(growable: false);

  static List<AttendanceStatus> get coachOnlyOptions =>
      values.where((status) => status.isCoachOnly).toList(growable: false);

  static AttendanceStatus fromFirestore(Object? value) {
    return switch (value) {
      'injured' => AttendanceStatus.injured,
      'court_only' => AttendanceStatus.courtOnly,
      'gym_only' => AttendanceStatus.gymOnly,
      'late' => AttendanceStatus.late,
      'absent' => AttendanceStatus.absent,
      'late_unannounced' => AttendanceStatus.lateUnannounced,
      'absent_unannounced' => AttendanceStatus.absentUnannounced,
      'absent_late_notice' => AttendanceStatus.absentLateNotice,
      _ => AttendanceStatus.attending,
    };
  }
}

int countAttendingPlayers({
  required Iterable<AppUser> members,
  required Map<String, AttendanceRecord> attendance,
  required DateTime sessionTime,
}) {
  return members
      .where((member) => member.active && member.role == UserRole.player)
      .where((member) {
        final status = resolveAttendanceStatus(
          user: member,
          explicitRecord: attendance[member.id],
          sessionTime: sessionTime,
        );
        return status.countsAsAttending;
      })
      .length;
}

AttendanceStatus resolveAttendanceStatus({
  required AppUser user,
  required AttendanceRecord? explicitRecord,
  required DateTime sessionTime,
}) {
  if (explicitRecord != null) {
    return explicitRecord.status;
  }
  if (user.teamMembershipStartedAt != null &&
      sessionTime.isBefore(user.teamMembershipStartedAt!)) {
    return AttendanceStatus.notApplicable;
  }
  return user.attendancePresumptionAt(sessionTime) ==
          AttendancePresumption.absent
      ? AttendanceStatus.absent
      : AttendanceStatus.attending;
}

class CoachAttendanceSummary {
  const CoachAttendanceSummary({
    required this.courtCount,
    required this.physicalCount,
    required this.latePlayerNames,
    required this.totalPlayers,
  });

  final int courtCount;
  final int physicalCount;
  final List<String> latePlayerNames;
  final int totalPlayers;
}

CoachAttendanceSummary buildCoachAttendanceSummary({
  required Iterable<AppUser> members,
  required Map<String, AttendanceRecord> attendance,
  required DateTime sessionTime,
}) {
  final players = members
      .where((member) => member.active && member.role == UserRole.player)
      .toList();
  var courtCount = 0;
  var physicalCount = 0;
  final latePlayerNames = <String>[];

  for (final player in players) {
    final status = resolveAttendanceStatus(
      user: player,
      explicitRecord: attendance[player.id],
      sessionTime: sessionTime,
    );
    final playerStatus = status.playerEquivalent;
    if (playerStatus == AttendanceStatus.attending ||
        playerStatus == AttendanceStatus.courtOnly ||
        playerStatus == AttendanceStatus.late) {
      courtCount++;
    }
    if (playerStatus == AttendanceStatus.attending ||
        playerStatus == AttendanceStatus.gymOnly ||
        playerStatus == AttendanceStatus.late) {
      physicalCount++;
    }
    if (playerStatus == AttendanceStatus.late) {
      latePlayerNames.add(player.fullName);
    }
  }
  latePlayerNames.sort(
    (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
  );

  final eligiblePlayerCount = players.where((player) {
    return resolveAttendanceStatus(
          user: player,
          explicitRecord: attendance[player.id],
          sessionTime: sessionTime,
        ) !=
        AttendanceStatus.notApplicable;
  }).length;

  return CoachAttendanceSummary(
    courtCount: courtCount,
    physicalCount: physicalCount,
    latePlayerNames: latePlayerNames,
    totalPlayers: eligiblePlayerCount,
  );
}

class PlayerAttendanceStats {
  const PlayerAttendanceStats({
    required this.userId,
    required this.sessionCount,
    required this.eligibleSessionCount,
    required this.attendedSessionCount,
    required this.attendanceCount,
    required this.lateCount,
    required this.physicalCount,
    required this.courtCount,
    required this.absenceCount,
    required this.injuryCount,
  });

  final String userId;
  final int sessionCount;
  final int eligibleSessionCount;
  final int attendedSessionCount;
  final int attendanceCount;
  final int lateCount;
  final int physicalCount;
  final int courtCount;
  final int absenceCount;
  final int injuryCount;

  int? get attendancePercentage => eligibleSessionCount == 0
      ? null
      : (attendedSessionCount * 100 / eligibleSessionCount).round();
}

class AttendanceHistorySnapshot {
  const AttendanceHistorySnapshot({
    required this.attendanceBySession,
    required this.loadedSessionIds,
    required this.totalSessionCount,
  });

  final Map<String, Map<String, AttendanceRecord>> attendanceBySession;
  final Set<String> loadedSessionIds;
  final int totalSessionCount;

  bool get isComplete => loadedSessionIds.length == totalSessionCount;
}

PlayerAttendanceStats buildPlayerAttendanceStats({
  required AppUser player,
  required Iterable<TeamSession> sessions,
  required Map<String, Map<String, AttendanceRecord>> attendanceBySession,
}) {
  var sessionCount = 0;
  var eligibleSessionCount = 0;
  var attendedSessionCount = 0;
  var attendanceCount = 0;
  var lateCount = 0;
  var physicalCount = 0;
  var courtCount = 0;
  var absenceCount = 0;
  var injuryCount = 0;

  for (final session in sessions) {
    final status = resolveAttendanceStatus(
      user: player,
      explicitRecord: attendanceBySession[session.id]?[player.id],
      sessionTime: session.startTime,
    );
    if (status == AttendanceStatus.notApplicable) {
      continue;
    }
    sessionCount++;
    if (status.isAttendancePercentageEligible) {
      eligibleSessionCount++;
    }
    if (status.countsForAttendancePercentage) {
      attendedSessionCount++;
    }
    switch (status) {
      case AttendanceStatus.attending:
        attendanceCount++;
        physicalCount++;
        courtCount++;
      case AttendanceStatus.late:
      case AttendanceStatus.lateUnannounced:
        lateCount++;
        physicalCount++;
      case AttendanceStatus.gymOnly:
        physicalCount++;
      case AttendanceStatus.courtOnly:
        courtCount++;
      case AttendanceStatus.absent:
      case AttendanceStatus.absentUnannounced:
      case AttendanceStatus.absentLateNotice:
        absenceCount++;
      case AttendanceStatus.injured:
        injuryCount++;
      case AttendanceStatus.notApplicable:
        break;
    }
  }

  return PlayerAttendanceStats(
    userId: player.id,
    sessionCount: sessionCount,
    eligibleSessionCount: eligibleSessionCount,
    attendedSessionCount: attendedSessionCount,
    attendanceCount: attendanceCount,
    lateCount: lateCount,
    physicalCount: physicalCount,
    courtCount: courtCount,
    absenceCount: absenceCount,
    injuryCount: injuryCount,
  );
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.userId,
    required this.status,
    this.note,
    this.updatedBy,
    this.updatedAt,
  });

  factory AttendanceRecord.attending(String userId) {
    return AttendanceRecord(userId: userId, status: AttendanceStatus.attending);
  }

  factory AttendanceRecord.defaultFor({
    required AppUser user,
    required DateTime sessionTime,
  }) {
    return AttendanceRecord(
      userId: user.id,
      status: resolveAttendanceStatus(
        user: user,
        explicitRecord: null,
        sessionTime: sessionTime,
      ),
    );
  }

  final String userId;
  final AttendanceStatus status;
  final String? note;
  final String? updatedBy;
  final DateTime? updatedAt;

  factory AttendanceRecord.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) {
      return AttendanceRecord.attending(snapshot.id);
    }
    return AttendanceRecord(
      userId: snapshot.id,
      status: AttendanceStatus.fromFirestore(data['status']),
      note: data['note'] as String?,
      updatedBy: data['updatedBy'] as String?,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class AttendanceDraft {
  const AttendanceDraft({required this.status, required this.note});

  final AttendanceStatus status;
  final String note;
}
