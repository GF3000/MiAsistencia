import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_user.dart';
import 'team_membership.dart';
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
  noConvocado,
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
    AttendanceStatus.noConvocado => 'no_convocado',
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
    AttendanceStatus.noConvocado => 'No convocado',
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
    AttendanceStatus.noConvocado => 'No convocado',
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
    AttendanceStatus.noConvocado => Icons.block_outlined,
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
    AttendanceStatus.noConvocado => const Color(0xFF475569),
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
      this != AttendanceStatus.noConvocado &&
      this != AttendanceStatus.notApplicable;

  bool get isCoachOnly =>
      this == AttendanceStatus.lateUnannounced ||
      this == AttendanceStatus.absentUnannounced ||
      this == AttendanceStatus.absentLateNotice ||
      this == AttendanceStatus.noConvocado;

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
      'no_convocado' => AttendanceStatus.noConvocado,
      _ => AttendanceStatus.attending,
    };
  }
}

/// Attendance of a session split by attendance presumption: [attending] of
/// the [expected] players presumed to attend do attend, plus [extra] players
/// presumed absent who attend anyway. Players who are not applicable or not
/// called up (`no_convocado`) are left out of both groups.
class PresumptionAttendanceCount {
  const PresumptionAttendanceCount({
    required this.attending,
    required this.expected,
    required this.extra,
  });

  final int attending;
  final int expected;
  final int extra;

  /// `14/17 + 2`, or `14/17` when no presumed-absent player attends.
  String get label =>
      extra > 0 ? '$attending/$expected + $extra' : '$attending/$expected';
}

PresumptionAttendanceCount countPlayersByPresumption({
  required Iterable<TeamRosterMember> members,
  required Map<String, AttendanceRecord> attendance,
  required DateTime sessionTime,
  required bool Function(AttendanceStatus status) attends,
}) {
  var attending = 0;
  var expected = 0;
  var extra = 0;
  for (final member in members) {
    if (!member.active || member.role != UserRole.player) {
      continue;
    }
    final status = resolveAttendanceStatus(
      user: member,
      explicitRecord: attendance[member.id],
      sessionTime: sessionTime,
    );
    if (status == AttendanceStatus.notApplicable ||
        status == AttendanceStatus.noConvocado) {
      continue;
    }
    if (isPresumedAbsentAt(member: member, sessionTime: sessionTime)) {
      if (attends(status)) {
        extra++;
      }
      continue;
    }
    expected++;
    if (attends(status)) {
      attending++;
    }
  }
  return PresumptionAttendanceCount(
    attending: attending,
    expected: expected,
    extra: extra,
  );
}

PresumptionAttendanceCount countAttendingPlayers({
  required Iterable<TeamRosterMember> members,
  required Map<String, AttendanceRecord> attendance,
  required DateTime sessionTime,
}) {
  return countPlayersByPresumption(
    members: members,
    attendance: attendance,
    sessionTime: sessionTime,
    attends: (status) => status.countsAsAttending,
  );
}

AttendanceStatus resolveAttendanceStatus({
  required TeamRosterMember user,
  required AttendanceRecord? explicitRecord,
  required DateTime sessionTime,
}) {
  if (explicitRecord != null) {
    return explicitRecord.status;
  }
  if (!user.isActiveAt(sessionTime)) {
    return AttendanceStatus.notApplicable;
  }
  return user.attendancePresumptionAt(sessionTime) ==
          AttendancePresumption.absent
      ? AttendanceStatus.absent
      : AttendanceStatus.attending;
}

class CoachAttendanceSummary {
  const CoachAttendanceSummary({
    required this.court,
    required this.physical,
    required this.latePlayerNames,
  });

  final PresumptionAttendanceCount court;
  final PresumptionAttendanceCount physical;
  final List<String> latePlayerNames;

  int get courtCount => court.attending;
  int get physicalCount => physical.attending;
  int get totalPlayers => court.expected;
}

/// Maps each full name to the shortest unambiguous form within [fullNames]:
/// the first name when no one else shares it, otherwise first name plus first
/// surname, falling back to the full name if that still collides.
Map<String, String> buildShortPlayerNames(Iterable<String> fullNames) {
  List<String> words(String name) =>
      name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  String prefix(String name, int count) => words(name).take(count).join(' ');
  Map<String, int> counts(Iterable<String> keys) {
    final result = <String, int>{};
    for (final key in keys) {
      result.update(key.toLowerCase(), (n) => n + 1, ifAbsent: () => 1);
    }
    return result;
  }

  final names = fullNames.toList();
  final firstNameCounts = counts(names.map((name) => prefix(name, 1)));
  final twoWordCounts = counts(names.map((name) => prefix(name, 2)));
  return {
    for (final name in names)
      name: firstNameCounts[prefix(name, 1).toLowerCase()] == 1
          ? prefix(name, 1)
          : twoWordCounts[prefix(name, 2).toLowerCase()] == 1
          ? prefix(name, 2)
          : name.trim(),
  };
}

CoachAttendanceSummary buildCoachAttendanceSummary({
  required Iterable<TeamRosterMember> members,
  required Map<String, AttendanceRecord> attendance,
  required DateTime sessionTime,
}) {
  final players = members
      .where((member) => member.active && member.role == UserRole.player)
      .toList();
  final shortNames = buildShortPlayerNames(
    players.map((player) => player.fullName),
  );
  final latePlayerNames = <String>[];
  for (final player in players) {
    final status = resolveAttendanceStatus(
      user: player,
      explicitRecord: attendance[player.id],
      sessionTime: sessionTime,
    );
    if (status.playerEquivalent == AttendanceStatus.late) {
      latePlayerNames.add(shortNames[player.fullName] ?? player.fullName);
    }
  }
  latePlayerNames.sort(
    (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
  );

  return CoachAttendanceSummary(
    court: countPlayersByPresumption(
      members: players,
      attendance: attendance,
      sessionTime: sessionTime,
      attends: (status) => switch (status.playerEquivalent) {
        AttendanceStatus.attending ||
        AttendanceStatus.courtOnly ||
        AttendanceStatus.late => true,
        _ => false,
      },
    ),
    physical: countPlayersByPresumption(
      members: players,
      attendance: attendance,
      sessionTime: sessionTime,
      attends: (status) => switch (status.playerEquivalent) {
        AttendanceStatus.attending ||
        AttendanceStatus.gymOnly ||
        AttendanceStatus.late => true,
        _ => false,
      },
    ),
    latePlayerNames: latePlayerNames,
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

PlayerAttendanceStats buildPlayerAttendanceStats({
  required TeamRosterMember player,
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
    if (isPresumedAbsentAt(member: player, sessionTime: session.startTime)) {
      continue;
    }
    final status = resolveAttendanceStatus(
      user: player,
      explicitRecord: attendanceBySession[session.id]?[player.id],
      sessionTime: session.startTime,
    );
    if (status == AttendanceStatus.notApplicable ||
        status == AttendanceStatus.noConvocado) {
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
      case AttendanceStatus.noConvocado:
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
    required TeamRosterMember user,
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

/// Pure transformation from the server-maintained `attendanceIndex` mirror
/// (memberId -> that member's raw `statuses` field, of otherwise-unknown
/// shape) into the `attendanceBySession` map the stat/chart/CSV builders
/// take.
///
/// Defensive by design: a malformed `statuses` value (or a malformed key
/// within it) for one member is skipped rather than thrown, so one corrupt
/// document can never break every player's data — matching the fallback
/// behavior [AttendanceStatus.fromFirestore] already applies to an
/// unrecognized status value.
Map<String, Map<String, AttendanceRecord>> buildAttendanceBySessionFromIndex(
  Map<String, Object?> rawStatusesByMemberId,
) {
  final attendanceBySession = <String, Map<String, AttendanceRecord>>{};
  for (final memberEntry in rawStatusesByMemberId.entries) {
    final memberId = memberEntry.key;
    final rawStatuses = memberEntry.value;
    if (rawStatuses is! Map) {
      continue;
    }
    for (final statusEntry in rawStatuses.entries) {
      final sessionId = statusEntry.key;
      if (sessionId is! String) {
        continue;
      }
      attendanceBySession
              .putIfAbsent(sessionId, () => <String, AttendanceRecord>{})[memberId] =
          AttendanceRecord(
            userId: memberId,
            status: AttendanceStatus.fromFirestore(statusEntry.value),
          );
    }
  }
  return attendanceBySession;
}
