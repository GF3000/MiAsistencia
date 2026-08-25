import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/team_membership.dart';

const _teamCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
final _teamCodePattern = RegExp(r'^[A-HJ-KM-NP-Z2-9]{6}$');

String generateTeamCode([Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(
    6,
    (_) => _teamCodeAlphabet[source.nextInt(_teamCodeAlphabet.length)],
  ).join();
}

String? normalizeTeamCode(String? code) {
  final normalized = code?.trim().toUpperCase();
  if (normalized == null || !_teamCodePattern.hasMatch(normalized)) {
    return null;
  }
  return normalized;
}

class TeamException implements Exception {
  const TeamException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum _JoinOutcome {
  joined,
  alreadyMember,
  unavailableTeam,
  missingProfile,
  coachCannotSwitch,
  switchNotConfirmed,
}

class TeamRepository {
  TeamRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _memberships =>
      _firestore.collection('teamMemberships');

  // --- Reads --------------------------------------------------------------

  Stream<Team?> watchTeam(String teamId) {
    return _firestore
        .collection('teams')
        .doc(teamId)
        .snapshots()
        .map(
          (snapshot) => snapshot.exists ? Team.fromSnapshot(snapshot) : null,
        );
  }

  /// Legacy roster read: active members from `users` (kept during the
  /// single-team bridge). Prefer [watchTeamMembers] once the UI consumes V2.
  Stream<List<AppUser>> watchMembers(String teamId) {
    return _firestore
        .collection('users')
        .where('teamId', isEqualTo: teamId)
        .snapshots()
        .map((snapshot) {
          final members = snapshot.docs
              .map(AppUser.fromSnapshot)
              .where((user) => user.active)
              .toList();
          members.sort(
            (left, right) => left.fullName.toLowerCase().compareTo(
              right.fullName.toLowerCase(),
            ),
          );
          return members;
        });
  }

  /// Active roster members from `teamMemberships`, ordered by name.
  Stream<List<TeamMembership>> watchTeamMembers(String teamId) {
    return _memberships
        .where('teamId', isEqualTo: teamId)
        .where('active', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final members = snapshot.docs
              .map(TeamMembership.fromSnapshot)
              .toList();
          members.sort(
            (left, right) => left.fullName.toLowerCase().compareTo(
              right.fullName.toLowerCase(),
            ),
          );
          return members;
        });
  }

  /// Every membership whose [TeamMembership.userId] is [userId], most recent
  /// first (used by the team selector / multi-team navigation).
  Stream<List<TeamMembership>> watchMembershipsForUser(String userId) {
    return _memberships
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final memberships = snapshot.docs
              .map(TeamMembership.fromSnapshot)
              .toList()
            ..sort(
              (left, right) => (left.updatedAt ?? left.createdAt ?? DateTime(0))
                  .compareTo(right.updatedAt ?? right.createdAt ?? DateTime(0)),
            );
          return memberships.reversed.toList();
        });
  }

  Stream<TeamMembership?> watchMembership(String teamId, String memberId) {
    return _memberships
        .doc(teamMembershipDocId(teamId, memberId))
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.exists ? TeamMembership.fromSnapshot(snapshot) : null,
        );
  }

  Future<Team?> findTeamByCode(String code) async {
    final normalizedCode = normalizeTeamCode(code);
    if (normalizedCode == null) {
      return null;
    }
    final snapshot = await _firestore
        .collection('teams')
        .doc(normalizedCode)
        .get();
    if (!snapshot.exists) {
      return null;
    }
    final team = Team.fromSnapshot(snapshot);
    return team.joinCode == normalizedCode ? team : null;
  }

  Future<Team?> getTeam(String teamId) async {
    final snapshot = await _firestore.collection('teams').doc(teamId).get();
    return snapshot.exists ? Team.fromSnapshot(snapshot) : null;
  }

  Future<String?> findPublicTeamName(String code) async {
    final normalizedCode = normalizeTeamCode(code);
    if (normalizedCode == null) {
      return null;
    }
    final snapshot = await _firestore
        .collection('teamInvites')
        .doc(normalizedCode)
        .get();
    if (!snapshot.exists) {
      return null;
    }
    final name = snapshot.data()?['name'];
    return name is String && name.trim().length >= 2 ? name.trim() : null;
  }

  Future<void> ensurePublicTeamInvitation(Team team) {
    return _firestore.collection('teamInvites').doc(team.id).set({
      'name': team.name,
    });
  }

  // --- Writes -------------------------------------------------------------

  /// Points the user's navigation preference at [teamId]. `activeTeamId` is a
  /// routing preference, not a membership; this never changes membership.
  Future<void> setActiveTeam({
    required String userId,
    required String? teamId,
  }) {
    return _firestore.collection('users').doc(userId).update({
      'activeTeamId': teamId,
      'membershipWriteToken': _newWriteToken(),
    });
  }

  Future<String> createTeam({
    required String name,
    required String userId,
  }) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final code = generateTeamCode();
      final teamReference = _firestore.collection('teams').doc(code);
      final invitationReference = _firestore
          .collection('teamInvites')
          .doc(code);
      final userReference = _firestore.collection('users').doc(userId);
      final membershipReference = _memberships
          .doc(teamMembershipDocId(code, userId));

      var collision = false;
      await _firestore.runTransaction((transaction) async {
        collision = false;
        final existingTeam = await transaction.get(teamReference);
        if (existingTeam.exists) {
          collision = true;
          return;
        }
        final userSnapshot = await transaction.get(userReference);
        if (!userSnapshot.exists) {
          throw const TeamException('No se pudo encontrar tu perfil.');
        }
        final user = AppUser.fromSnapshot(userSnapshot);

        transaction.set(teamReference, {
          'name': name.trim(),
          'joinCode': code,
          'createdBy': userId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.set(invitationReference, {'name': name.trim()});
        transaction.set(
          membershipReference,
          _newMembershipData(
            teamId: code,
            memberId: userId,
            userId: userId,
            fullName: user.fullName,
            email: user.email,
            role: UserRole.admin,
            active: true,
            managedByCoach: false,
            membershipPeriods: [_openPeriod()],
            attendancePresumption: AttendancePresumption.attending,
          ),
        );
        transaction.update(userReference, {
          'teamId': code,
          'teamJoinedAt': FieldValue.serverTimestamp(),
          'role': UserRole.admin.firestoreValue,
          'attendanceDefaultStatus':
              AttendancePresumption.attending.firestoreValue,
          'attendanceDefaultHistory': [],
          'activeTeamId': code,
          'schemaVersion': 2,
          'membershipWriteToken': _newWriteToken(),
        });
      });
      if (!collision) {
        return code;
      }
    }
    throw const TeamException(
      'No se pudo generar un código de equipo. Inténtalo de nuevo.',
    );
  }

  Future<void> joinTeam({
    required String code,
    required String userId,
    bool allowTeamSwitch = false,
  }) async {
    final normalizedCode = normalizeTeamCode(code);
    if (normalizedCode == null) {
      throw const TeamException('El código de equipo no es válido.');
    }
    final team = await findTeamByCode(normalizedCode);
    if (team == null) {
      throw const TeamException('No encontramos ningún equipo con ese código.');
    }

    final teamReference = _firestore.collection('teams').doc(team.id);
    final userReference = _firestore.collection('users').doc(userId);
    final newMembershipReference = _memberships
        .doc(teamMembershipDocId(team.id, userId));
    _JoinOutcome? outcome;
    await _firestore.runTransaction((transaction) async {
      outcome = null;
      final teamSnapshot = await transaction.get(teamReference);
      final userSnapshot = await transaction.get(userReference);
      if (!teamSnapshot.exists ||
          Team.fromSnapshot(teamSnapshot).joinCode != normalizedCode) {
        outcome = _JoinOutcome.unavailableTeam;
        return;
      }
      if (!userSnapshot.exists) {
        outcome = _JoinOutcome.missingProfile;
        return;
      }

      final user = AppUser.fromSnapshot(userSnapshot);
      if (user.teamId == team.id) {
        outcome = _JoinOutcome.alreadyMember;
        return;
      }
      if (user.hasTeam && user.isCoach) {
        outcome = _JoinOutcome.coachCannotSwitch;
        return;
      }
      if (user.hasTeam && !allowTeamSwitch) {
        outcome = _JoinOutcome.switchNotConfirmed;
        return;
      }

      // Single-team bridge: close the membership of the team being left.
      final oldTeamId = user.teamId;
      if (oldTeamId != null && oldTeamId.isNotEmpty) {
        final oldMembershipReference = _memberships
            .doc(teamMembershipDocId(oldTeamId, userId));
        final oldMembershipSnapshot = await transaction.get(
          oldMembershipReference,
        );
        if (oldMembershipSnapshot.exists) {
          final old = TeamMembership.fromSnapshot(oldMembershipSnapshot);
          transaction.set(
            oldMembershipReference,
            _existingMembershipData(old, active: false, closeOpenPeriod: true),
          );
        }
      }

      final newMembershipSnapshot = await transaction.get(
        newMembershipReference,
      );
      if (newMembershipSnapshot.exists) {
        final existing = TeamMembership.fromSnapshot(newMembershipSnapshot);
        transaction.set(
          newMembershipReference,
          _existingMembershipData(existing, active: true, openNewPeriod: true),
        );
      } else {
        transaction.set(
          newMembershipReference,
          _newMembershipData(
            teamId: team.id,
            memberId: userId,
            userId: userId,
            fullName: user.fullName,
            email: user.email,
            role: UserRole.player,
            active: true,
            managedByCoach: false,
            membershipPeriods: [_openPeriod()],
            attendancePresumption: AttendancePresumption.attending,
          ),
        );
      }

      transaction.update(userReference, {
        'teamId': team.id,
        'teamJoinedAt': FieldValue.serverTimestamp(),
        'role': UserRole.player.firestoreValue,
        'attendanceDefaultStatus':
            AttendancePresumption.attending.firestoreValue,
        'attendanceDefaultHistory': [],
        'activeTeamId': team.id,
        'schemaVersion': 2,
        'membershipWriteToken': _newWriteToken(),
      });
      outcome = _JoinOutcome.joined;
    });

    switch (outcome) {
      case _JoinOutcome.joined || _JoinOutcome.alreadyMember:
        return;
      case _JoinOutcome.unavailableTeam:
        throw const TeamException(
          'La invitación ya no corresponde a un equipo disponible.',
        );
      case _JoinOutcome.missingProfile:
        throw const TeamException('No se pudo encontrar tu perfil.');
      case _JoinOutcome.coachCannotSwitch:
        throw const TeamException(
          'Los entrenadores no pueden cambiar de equipo sin transferir antes '
          'la gestión del equipo actual.',
        );
      case _JoinOutcome.switchNotConfirmed:
        throw const TeamException(
          'Confirma primero que quieres abandonar tu equipo actual.',
        );
      case null:
        throw const TeamException(
          'No se pudo completar el cambio de equipo. Inténtalo de nuevo.',
        );
    }
  }

  Future<void> leaveTeam({
    required String teamId,
    required String userId,
  }) async {
    final userReference = _firestore.collection('users').doc(userId);
    final membershipReference = _memberships
        .doc(teamMembershipDocId(teamId, userId));
    await _firestore.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userReference);
      if (!userSnapshot.exists) {
        throw const TeamException('No se pudo encontrar tu perfil.');
      }
      final user = AppUser.fromSnapshot(userSnapshot);
      if (user.teamId != teamId) {
        throw const TeamException('Ya no perteneces a este equipo.');
      }
      if (user.isCoach) {
        throw const TeamException(
          'Los entrenadores no pueden abandonar el equipo desde esta opción.',
        );
      }

      final membershipSnapshot = await transaction.get(membershipReference);
      if (membershipSnapshot.exists) {
        final membership = TeamMembership.fromSnapshot(membershipSnapshot);
        transaction.set(
          membershipReference,
          _existingMembershipData(
            membership,
            active: false,
            closeOpenPeriod: true,
          ),
        );
      }

      transaction.update(userReference, {
        'teamId': null,
        'teamJoinedAt': null,
        'role': UserRole.player.firestoreValue,
        'attendanceDefaultStatus': AttendancePresumption.attending.firestoreValue,
        'attendanceDefaultHistory': [],
        'activeTeamId': null,
        'schemaVersion': 2,
        'membershipWriteToken': _newWriteToken(),
      });
    });
  }

  Future<void> createManagedPlayer({
    required String teamId,
    required String actingUserId,
    required String fullName,
  }) async {
    final normalizedName = fullName.trim();
    if (normalizedName.length < 2) {
      throw const TeamException('Escribe el nombre del jugador.');
    }

    final teamReference = _firestore.collection('teams').doc(teamId);
    final actorReference = _firestore.collection('users').doc(actingUserId);
    final playerReference = _firestore.collection('users').doc();
    final membershipReference = _memberships
        .doc(teamMembershipDocId(teamId, playerReference.id));

    await _firestore.runTransaction((transaction) async {
      final teamSnapshot = await transaction.get(teamReference);
      final actorSnapshot = await transaction.get(actorReference);
      if (!teamSnapshot.exists) {
        throw const TeamException('El equipo ya no existe.');
      }
      if (!actorSnapshot.exists) {
        throw const TeamException('No se pudo comprobar tu acceso.');
      }
      final actor = AppUser.fromSnapshot(actorSnapshot);
      if (actor.teamId != teamId || !actor.isCoach) {
        throw const TeamException(
          'Sólo los entrenadores pueden añadir jugadores.',
        );
      }

      transaction.set(playerReference, {
        'email': '',
        'fullName': normalizedName,
        'role': UserRole.player.firestoreValue,
        'teamId': teamId,
        'teamJoinedAt': FieldValue.serverTimestamp(),
        'active': true,
        'managedByCoach': true,
        'attendanceDefaultStatus':
            AttendancePresumption.attending.firestoreValue,
        'attendanceDefaultHistory': [],
        'createdAt': FieldValue.serverTimestamp(),
        'schemaVersion': 2,
        'membershipWriteToken': _newWriteToken(),
      });
      transaction.set(
        membershipReference,
        _newMembershipData(
          teamId: teamId,
          memberId: playerReference.id,
          userId: null,
          fullName: normalizedName,
          email: '',
          role: UserRole.player,
          active: true,
          managedByCoach: true,
          membershipPeriods: [_openPeriod()],
          attendancePresumption: AttendancePresumption.attending,
        ),
      );
    });
  }

  Future<void> updateMemberRole({
    required String teamId,
    required String memberId,
    required String actingUserId,
    required UserRole role,
  }) {
    return _manageMember(
      teamId: teamId,
      memberId: memberId,
      actingUserId: actingUserId,
      validate: (member) {
        if (member.managedByCoach && role == UserRole.admin) {
          throw const TeamException(
            'Un jugador sin cuenta no puede ser entrenador.',
          );
        }
      },
      update: (
        transaction,
        memberReference,
        membershipReference,
        member,
        membership,
      ) {
        transaction.update(memberReference, {
          'role': role.firestoreValue,
          'attendanceDefaultStatus':
              AttendancePresumption.attending.firestoreValue,
          'attendanceDefaultHistory': [],
          'membershipWriteToken': _newWriteToken(),
        });
        if (membership != null) {
          transaction.set(
            membershipReference,
            _existingMembershipData(
              membership,
              role: role,
              attendancePresumption: AttendancePresumption.attending,
              attendanceHistory: const [],
            ),
          );
        }
      },
    );
  }

  Future<void> removeMember({
    required String teamId,
    required String memberId,
    required String actingUserId,
  }) {
    return _manageMember(
      teamId: teamId,
      memberId: memberId,
      actingUserId: actingUserId,
      update: (
        transaction,
        memberReference,
        membershipReference,
        member,
        membership,
      ) {
        if (member.managedByCoach) {
          transaction.delete(memberReference);
          transaction.delete(membershipReference);
          return;
        }
        transaction.update(memberReference, {
          'teamId': null,
          'teamJoinedAt': null,
          'role': UserRole.player.firestoreValue,
          'attendanceDefaultStatus':
              AttendancePresumption.attending.firestoreValue,
          'attendanceDefaultHistory': [],
          'activeTeamId': null,
          'membershipWriteToken': _newWriteToken(),
        });
        if (membership != null) {
          transaction.set(
            membershipReference,
            _existingMembershipData(membership, active: false, closeOpenPeriod: true),
          );
        }
      },
    );
  }

  Future<void> updateAttendancePresumption({
    required String teamId,
    required String memberId,
    required String actingUserId,
    required AttendancePresumption value,
  }) {
    return _manageMember(
      teamId: teamId,
      memberId: memberId,
      actingUserId: actingUserId,
      validate: (member) {
        if (member.isCoach) {
          throw const TeamException(
            'La presunción de asistencia solo se aplica a jugadores.',
          );
        }
      },
      update: (
        transaction,
        memberReference,
        membershipReference,
        member,
        membership,
      ) {
        final historyEntry = {
          'status': value.firestoreValue,
          'effectiveFrom': Timestamp.now(),
        };
        transaction.update(memberReference, {
          'attendanceDefaultStatus': value.firestoreValue,
          'attendanceDefaultHistory': FieldValue.arrayUnion([historyEntry]),
          'membershipWriteToken': _newWriteToken(),
        });
        if (membership != null) {
          transaction.set(
            membershipReference,
            _existingMembershipData(
              membership,
              attendancePresumption: value,
              attendanceHistory: [
                ...membership.attendancePresumptionHistory,
                AttendancePresumptionChange(
                  value: value,
                  effectiveFrom: DateTime.now(),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  Future<void> _manageMember({
    required String teamId,
    required String memberId,
    required String actingUserId,
    required void Function(
      Transaction transaction,
      DocumentReference<Map<String, dynamic>> memberReference,
      DocumentReference<Map<String, dynamic>> membershipReference,
      AppUser member,
      TeamMembership? membership,
    )
    update,
    void Function(AppUser member)? validate,
  }) {
    if (memberId == actingUserId) {
      throw const TeamException(
        'No puedes cambiar tu propio acceso desde esta pantalla.',
      );
    }

    final teamReference = _firestore.collection('teams').doc(teamId);
    final actorReference = _firestore.collection('users').doc(actingUserId);
    final memberReference = _firestore.collection('users').doc(memberId);
    final membershipReference = _memberships
        .doc(teamMembershipDocId(teamId, memberId));

    return _firestore.runTransaction((transaction) async {
      final teamSnapshot = await transaction.get(teamReference);
      final actorSnapshot = await transaction.get(actorReference);
      final memberSnapshot = await transaction.get(memberReference);

      if (!teamSnapshot.exists) {
        throw const TeamException('El equipo ya no existe.');
      }
      if (!actorSnapshot.exists) {
        throw const TeamException('No se pudo comprobar tu acceso.');
      }
      final actor = AppUser.fromSnapshot(actorSnapshot);
      if (actor.teamId != teamId || !actor.isCoach) {
        throw const TeamException(
          'Sólo los entrenadores pueden administrar el equipo.',
        );
      }
      if (!memberSnapshot.exists) {
        throw const TeamException('Este miembro ya no está disponible.');
      }
      final member = AppUser.fromSnapshot(memberSnapshot);
      if (member.teamId != teamId) {
        throw const TeamException('Este miembro ya no pertenece al equipo.');
      }
      final team = Team.fromSnapshot(teamSnapshot);
      if (team.createdBy == memberId) {
        throw const TeamException(
          'El propietario del equipo debe seguir siendo entrenador.',
        );
      }

      validate?.call(member);
      final membershipSnapshot = await transaction.get(membershipReference);
      final membership = membershipSnapshot.exists
          ? TeamMembership.fromSnapshot(membershipSnapshot)
          : null;
      update(
        transaction,
        memberReference,
        membershipReference,
        member,
        membership,
      );
    });
  }

  // --- Write helpers ------------------------------------------------------

  String _newWriteToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Map<String, dynamic> _openPeriod() {
    return {'joinedAt': FieldValue.serverTimestamp(), 'leftAt': null};
  }

  Map<String, dynamic> _periodToWrite(MembershipPeriod period) {
    return {
      'joinedAt': Timestamp.fromDate(period.joinedAt),
      'leftAt': period.leftAt == null
          ? null
          : Timestamp.fromDate(period.leftAt!),
    };
  }

  List<Map<String, dynamic>> _historyToWrite(
    List<AttendancePresumptionChange> history,
  ) {
    return history
        .map(
          (change) => {
            'status': change.value.firestoreValue,
            'effectiveFrom': Timestamp.fromDate(change.effectiveFrom),
          },
        )
        .toList();
  }

  Map<String, dynamic> _newMembershipData({
    required String teamId,
    required String memberId,
    required String? userId,
    required String fullName,
    required String email,
    required UserRole role,
    required bool active,
    required bool managedByCoach,
    required List<Map<String, dynamic>> membershipPeriods,
    required AttendancePresumption attendancePresumption,
  }) {
    return {
      'teamId': teamId,
      'memberId': memberId,
      'userId': userId,
      'fullName': fullName,
      'email': email,
      'role': role.firestoreValue,
      'active': active,
      'managedByCoach': managedByCoach,
      'membershipPeriods': membershipPeriods,
      'attendanceDefaultStatus': attendancePresumption.firestoreValue,
      'attendanceDefaultHistory': [],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'migrationVersion': 2,
    };
  }

  Map<String, dynamic> _existingMembershipData(
    TeamMembership membership, {
    bool? active,
    bool closeOpenPeriod = false,
    bool openNewPeriod = false,
    UserRole? role,
    AttendancePresumption? attendancePresumption,
    List<AttendancePresumptionChange>? attendanceHistory,
  }) {
    var periods = membership.membershipPeriods;
    if (closeOpenPeriod) {
      periods = periods.map((period) {
        if (!period.isOpen) {
          return period;
        }
        return MembershipPeriod(
          joinedAt: period.joinedAt,
          leftAt: DateTime.now(),
        );
      }).toList();
    }
    if (openNewPeriod && !periods.any((period) => period.isOpen)) {
      periods = [
        ...periods,
        MembershipPeriod(joinedAt: DateTime.now(), leftAt: null),
      ];
    }
    final history = attendanceHistory ?? membership.attendancePresumptionHistory;
    return {
      'teamId': membership.teamId,
      'memberId': membership.memberId,
      'userId': membership.userId,
      'fullName': membership.fullName,
      'email': membership.email,
      'role': (role ?? membership.role).firestoreValue,
      'active': active ?? membership.active,
      'managedByCoach': membership.managedByCoach,
      'membershipPeriods': periods.map(_periodToWrite).toList(),
      'attendanceDefaultStatus': (attendancePresumption ??
              membership.attendancePresumption)
          .firestoreValue,
      'attendanceDefaultHistory': _historyToWrite(history),
      'createdAt': membership.createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(membership.createdAt!),
      'updatedAt': FieldValue.serverTimestamp(),
      'migrationVersion': membership.migrationVersion ?? 2,
    };
  }
}
