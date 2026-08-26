import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';

/// Deterministic document id for a [TeamMembership]: `{teamId}__{memberId}`.
/// Kept in sync with `buildMembershipId` in `functions/src/migrationIds.ts`.
String teamMembershipDocId(String teamId, String memberId) =>
    '${teamId}__$memberId';

/// Read-only contract consumed by the pure attendance and ranking functions
/// in `attendance.dart` and `player_motivation.dart`.
///
/// Both the legacy [AppUser] profile and the new [TeamMembership] record
/// implement this interface so those functions can operate on either
/// representation while the migration to per-team membership documents is
/// rolled out incrementally, without forcing every caller to switch at once.
abstract interface class TeamRosterMember {
  /// Identifier used as the attendance subcollection document id and as the
  /// map key throughout attendance/ranking calculations. It must stay stable
  /// across the migration, including for managed players without accounts.
  String get id;

  String get fullName;

  String get email;

  UserRole get role;

  bool get isCoach;

  /// Whether this member currently counts towards the roster.
  bool get active;

  /// The team this member belongs to. Null only for a legacy profile that has
  /// no team yet.
  String? get teamId;

  bool get managedByCoach;

  bool get hasAccount;

  /// The base attendance presumption (without applying the change history).
  AttendancePresumption get attendancePresumption;

  bool get canLeaveTeam;

  /// The instant from which this member's presence should be evaluated.
  /// Sessions scheduled before this instant resolve as
  /// `AttendanceStatus.notApplicable`.
  DateTime? get teamMembershipStartedAt;

  /// Whether this member belonged to the team at [instant].
  bool isActiveAt(DateTime instant);

  AttendancePresumption attendancePresumptionAt(DateTime sessionTime);
}

/// Resolves the [AttendancePresumption] in effect at [sessionTime], given a
/// [base] default and a chronologically unordered [history] of changes.
///
/// Shared by [AppUser] and [TeamMembership] so both keep identical semantics.
AttendancePresumption resolveAttendancePresumptionAt({
  required AttendancePresumption base,
  required List<AttendancePresumptionChange> history,
  required DateTime sessionTime,
}) {
  var resolved = AttendancePresumption.attending;
  final ordered = [...history]
    ..sort((left, right) => left.effectiveFrom.compareTo(right.effectiveFrom));
  for (final change in ordered) {
    if (change.effectiveFrom.isAfter(sessionTime)) {
      break;
    }
    resolved = change.value;
  }
  return ordered.isEmpty ? base : resolved;
}

/// Whether [member] was presumed absent (i.e. not expected to attend) at
/// [sessionTime]. Such sessions are excluded from attendance percentages.
bool isPresumedAbsentAt({
  required TeamRosterMember member,
  required DateTime sessionTime,
}) {
  return member.attendancePresumptionAt(sessionTime) ==
      AttendancePresumption.absent;
}

/// A single continuous span of membership in a team, using
/// `[joinedAt, leftAt)` semantics: [joinedAt] is inclusive, [leftAt] is
/// exclusive. An open (current) period has a null [leftAt].
class MembershipPeriod {
  const MembershipPeriod({required this.joinedAt, this.leftAt});

  final DateTime joinedAt;
  final DateTime? leftAt;

  bool get isOpen => leftAt == null;

  /// Whether [instant] falls within `[joinedAt, leftAt)`.
  bool isActiveAt(DateTime instant) {
    if (instant.isBefore(joinedAt)) {
      return false;
    }
    final left = leftAt;
    return left == null || instant.isBefore(left);
  }

  factory MembershipPeriod.fromFirestore(Map<String, dynamic> data) {
    final joinedAt = data['joinedAt'];
    if (joinedAt is! Timestamp) {
      throw const FormatException(
        'Membership periods require a joinedAt timestamp.',
      );
    }
    return MembershipPeriod(
      joinedAt: joinedAt.toDate(),
      leftAt: (data['leftAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'joinedAt': Timestamp.fromDate(joinedAt),
      'leftAt': leftAt == null ? null : Timestamp.fromDate(leftAt!),
    };
  }

  MembershipPeriod copyWith({DateTime? joinedAt, DateTime? leftAt}) {
    return MembershipPeriod(
      joinedAt: joinedAt ?? this.joinedAt,
      leftAt: leftAt ?? this.leftAt,
    );
  }
}

/// Per-team roster record that replaces the single global `teamId` carried
/// today on [AppUser]. A user (or a coach-managed player without an account)
/// gets one [TeamMembership] document per team they belong to.
///
/// [memberId] is preserved explicitly (rather than always derived from a
/// linked account) so that existing `sessions/{sessionId}/attendance/{id}`
/// documents keep referencing the same id across the migration, including
/// for managed players who never had a [userId].
class TeamMembership implements TeamRosterMember {
  const TeamMembership({
    required this.teamId,
    required this.memberId,
    required this.fullName,
    required this.email,
    required this.role,
    required this.active,
    this.userId,
    this.managedByCoach = false,
    this.membershipPeriods = const [],
    this.attendancePresumption = AttendancePresumption.attending,
    this.attendancePresumptionHistory = const [],
    this.createdAt,
    this.updatedAt,
    this.migrationVersion,
  });

  @override
  final String teamId;

  /// Stable identifier of this roster entry. For members with an account
  /// this is typically the same as [userId]; for coach-managed players it is
  /// an app-generated id that has no corresponding auth user.
  final String memberId;

  /// Null for coach-managed players who have no linked Firebase Auth user.
  final String? userId;

  @override
  final String fullName;
  @override
  final String email;
  @override
  final UserRole role;

  /// Flat "currently part of the roster" flag, mirrored from Firestore for
  /// cheap queries (e.g. security rules). Temporal eligibility for a given
  /// instant must go through [isActiveAt], not this flag alone.
  @override
  final bool active;

  @override
  final bool managedByCoach;

  /// Chronological join/leave history for this membership. May be empty for
  /// records migrated without period history; see [isActiveAt].
  final List<MembershipPeriod> membershipPeriods;

  @override
  final AttendancePresumption attendancePresumption;
  final List<AttendancePresumptionChange> attendancePresumptionHistory;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Schema/migration marker written by the backfill so functions and
  /// repositories can distinguish already-migrated documents.
  final int? migrationVersion;

  @override
  String get id => memberId;

  @override
  bool get isCoach => role.isCoach;

  @override
  bool get hasAccount => userId != null;

  @override
  bool get canLeaveTeam => role == UserRole.player && hasAccount && active;

  /// The still-open period (no [MembershipPeriod.leftAt]), if any.
  MembershipPeriod? get openPeriod {
    for (final period in membershipPeriods) {
      if (period.isOpen) {
        return period;
      }
    }
    return null;
  }

  /// The most relevant period: the open one if present, otherwise the most
  /// recently closed one. Null when there is no period history at all.
  MembershipPeriod? get currentPeriod {
    if (membershipPeriods.isEmpty) {
      return null;
    }
    final open = openPeriod;
    if (open != null) {
      return open;
    }
    final ordered = [...membershipPeriods]
      ..sort((left, right) => left.joinedAt.compareTo(right.joinedAt));
    return ordered.last;
  }

  @override
  DateTime? get teamMembershipStartedAt {
    if (membershipPeriods.isEmpty) {
      return createdAt;
    }
    final ordered = [...membershipPeriods]
      ..sort((left, right) => left.joinedAt.compareTo(right.joinedAt));
    return ordered.first.joinedAt;
  }

  /// Whether this membership was active at [instant], consulting every
  /// period rather than only the flat [active] flag.
  ///
  /// Defensive behavior for legacy/empty [membershipPeriods] (e.g. records
  /// migrated before period history existed): falls back to the [active]
  /// flag, bounded below by [createdAt] when known, so members never appear
  /// active before their record existed.
  @override
  bool isActiveAt(DateTime instant) {
    if (membershipPeriods.isEmpty) {
      final legacyStart = createdAt;
      if (legacyStart != null && instant.isBefore(legacyStart)) {
        return false;
      }
      return active;
    }
    return membershipPeriods.any((period) => period.isActiveAt(instant));
  }

  @override
  AttendancePresumption attendancePresumptionAt(DateTime sessionTime) {
    return resolveAttendancePresumptionAt(
      base: attendancePresumption,
      history: attendancePresumptionHistory,
      sessionTime: sessionTime,
    );
  }

  /// Parses a membership document body. Kept separate from [fromSnapshot] so
  /// it can be exercised in tests without a live `DocumentSnapshot`, and so
  /// repositories/Cloud Functions can share the same field expectations.
  factory TeamMembership.fromFirestore(
    Map<String, dynamic> data, {
    required String documentId,
  }) {
    return TeamMembership(
      teamId: data['teamId'] as String? ?? '',
      memberId: data['memberId'] as String? ?? documentId,
      userId: data['userId'] as String?,
      fullName: data['fullName'] as String? ?? 'Jugador',
      email: data['email'] as String? ?? '',
      role: UserRole.fromFirestore(data['role']),
      active: data['active'] as bool? ?? true,
      managedByCoach: data['managedByCoach'] as bool? ?? false,
      membershipPeriods:
          (data['membershipPeriods'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(MembershipPeriod.fromFirestore)
              .toList(),
      attendancePresumption: AttendancePresumption.fromFirestore(
        data['attendanceDefaultStatus'],
      ),
      attendancePresumptionHistory:
          (data['attendanceDefaultHistory'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(AttendancePresumptionChange.fromFirestore)
              .toList(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      migrationVersion: data['migrationVersion'] as int?,
    );
  }

  factory TeamMembership.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return TeamMembership.fromFirestore(
      snapshot.data() ?? const <String, dynamic>{},
      documentId: snapshot.id,
    );
  }

  /// Map representation using Dart client [Timestamp]s, matching the
  /// conventions used across `lib/src/repositories`. Callers writing new
  /// documents should still stamp `createdAt`/`updatedAt` with
  /// `FieldValue.serverTimestamp()` rather than the values produced here.
  Map<String, dynamic> toMap() {
    return {
      'teamId': teamId,
      'memberId': memberId,
      'userId': userId,
      'fullName': fullName,
      'email': email,
      'role': role.firestoreValue,
      'active': active,
      'managedByCoach': managedByCoach,
      'membershipPeriods': membershipPeriods
          .map((period) => period.toMap())
          .toList(),
      'attendanceDefaultStatus': attendancePresumption.firestoreValue,
      'attendanceDefaultHistory': attendancePresumptionHistory
          .map(
            (change) => {
              'status': change.value.firestoreValue,
              'effectiveFrom': Timestamp.fromDate(change.effectiveFrom),
            },
          )
          .toList(),
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      if (migrationVersion != null) 'migrationVersion': migrationVersion,
    };
  }

  TeamMembership copyWith({
    bool? active,
    List<MembershipPeriod>? membershipPeriods,
    AttendancePresumption? attendancePresumption,
    List<AttendancePresumptionChange>? attendancePresumptionHistory,
    DateTime? updatedAt,
    int? migrationVersion,
  }) {
    return TeamMembership(
      teamId: teamId,
      memberId: memberId,
      userId: userId,
      fullName: fullName,
      email: email,
      role: role,
      active: active ?? this.active,
      managedByCoach: managedByCoach,
      membershipPeriods: membershipPeriods ?? this.membershipPeriods,
      attendancePresumption:
          attendancePresumption ?? this.attendancePresumption,
      attendancePresumptionHistory:
          attendancePresumptionHistory ?? this.attendancePresumptionHistory,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      migrationVersion: migrationVersion ?? this.migrationVersion,
    );
  }
}
