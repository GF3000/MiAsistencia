import 'package:cloud_firestore/cloud_firestore.dart';

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

class AppUser {
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
  });

  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final String? teamId;
  final bool active;
  final DateTime? teamJoinedAt;
  final DateTime? createdAt;
  final bool managedByCoach;
  final AttendancePresumption attendancePresumption;
  final List<AttendancePresumptionChange> attendancePresumptionHistory;

  bool get isCoach => role.isCoach;
  bool get hasAccount => !managedByCoach;
  bool get hasTeam => teamId != null && teamId!.isNotEmpty;
  bool get canLeaveTeam => role == UserRole.player && hasAccount && hasTeam;
  DateTime? get teamMembershipStartedAt => teamJoinedAt ?? createdAt;

  AttendancePresumption attendancePresumptionAt(DateTime sessionTime) {
    var resolved = AttendancePresumption.attending;
    final history = [
      ...attendancePresumptionHistory,
    ]..sort((left, right) => left.effectiveFrom.compareTo(right.effectiveFrom));
    for (final change in history) {
      if (change.effectiveFrom.isAfter(sessionTime)) {
        break;
      }
      resolved = change.value;
    }
    return history.isEmpty ? attendancePresumption : resolved;
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
