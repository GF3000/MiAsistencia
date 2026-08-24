import 'package:cloud_firestore/cloud_firestore.dart';

import 'team_membership.dart';

enum UserRole {
  admin,
  player;

  static UserRole fromFirestore(Object? value) {
    return value == 'admin' ? UserRole.admin : UserRole.player;
  }

  String get firestoreValue => name;
  String get label => this == UserRole.admin ? 'Entrenador' : 'Jugador';
  bool get isCoach => this == UserRole.admin;
}

enum AttendancePresumption {
  attending,
  absent;

  String get firestoreValue => name;
  String get label => this == attending ? 'Asiste' : 'No asiste';

  static AttendancePresumption fromFirestore(Object? value) {
    return value == 'absent' ? absent : attending;
  }
}

class AttendancePresumptionChange {
  const AttendancePresumptionChange({
    required this.value,
    required this.effectiveFrom,
  });

  final AttendancePresumption value;
  final DateTime effectiveFrom;

  factory AttendancePresumptionChange.fromFirestore(Map<String, dynamic> data) {
    return AttendancePresumptionChange(
      value: AttendancePresumption.fromFirestore(data['status']),
      effectiveFrom: (data['effectiveFrom'] as Timestamp).toDate(),
    );
  }
}

class AppUser implements TeamRosterMember {
  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.teamId,
    required this.active,
    this.teamJoinedAt,
    this.createdAt,
    this.managedByCoach = false,
    this.attendancePresumption = AttendancePresumption.attending,
    this.attendancePresumptionHistory = const [],
    this.activeTeamId,
    this.schemaVersion,
  });

  @override
  final String id;
  final String email;
  @override
  final String fullName;
  @override
  final UserRole role;
  final String? teamId;
  @override
  final bool active;
  final DateTime? teamJoinedAt;
  final DateTime? createdAt;
  final bool managedByCoach;
  final AttendancePresumption attendancePresumption;
  final List<AttendancePresumptionChange> attendancePresumptionHistory;

  /// Placeholder for the multi-team migration: once a user can belong to
  /// several [TeamMembership] documents, this marks which one currently
  /// drives their default routing/UI. Null keeps today's single-team
  /// behavior (driven by [teamId]) unchanged.
  final String? activeTeamId;

  /// Placeholder for the multi-team migration so profile documents written
  /// by a future backfill can be parsed defensively. Null means "legacy
  /// single-team profile".
  final int? schemaVersion;

  bool get isCoach => role.isCoach;
  bool get hasAccount => !managedByCoach;
  bool get hasTeam => teamId != null && teamId!.isNotEmpty;
  bool get canLeaveTeam => role == UserRole.player && hasAccount && hasTeam;
  @override
  DateTime? get teamMembershipStartedAt => teamJoinedAt ?? createdAt;

  @override
  bool isActiveAt(DateTime instant) {
    final startedAt = teamMembershipStartedAt;
    return startedAt == null || !instant.isBefore(startedAt);
  }

  @override
  AttendancePresumption attendancePresumptionAt(DateTime sessionTime) {
    return resolveAttendancePresumptionAt(
      base: attendancePresumption,
      history: attendancePresumptionHistory,
      sessionTime: sessionTime,
    );
  }

  factory AppUser.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return AppUser(
      id: snapshot.id,
      email: data['email'] as String? ?? '',
      fullName: data['fullName'] as String? ?? 'Jugador',
      role: UserRole.fromFirestore(data['role']),
      teamId: data['teamId'] as String?,
      active: data['active'] as bool? ?? true,
      teamJoinedAt: (data['teamJoinedAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      managedByCoach: data['managedByCoach'] as bool? ?? false,
      attendancePresumption: AttendancePresumption.fromFirestore(
        data['attendanceDefaultStatus'],
      ),
      attendancePresumptionHistory:
          (data['attendanceDefaultHistory'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(AttendancePresumptionChange.fromFirestore)
              .toList(),
      activeTeamId: data['activeTeamId'] as String?,
      schemaVersion: data['schemaVersion'] as int?,
    );
  }
}

class Team {
  const Team({
    required this.id,
    required this.name,
    required this.joinCode,
    required this.createdBy,
  });

  final String id;
  final String name;
  final String joinCode;
  final String createdBy;

  factory Team.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return Team(
      id: snapshot.id,
      name: data['name'] as String? ?? 'Mi equipo',
      joinCode: data['joinCode'] as String? ?? snapshot.id,
      createdBy: data['createdBy'] as String? ?? '',
    );
  }
}
