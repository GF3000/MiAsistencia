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

/// Throws unless [actor] is an active coach membership of [teamId].
///
/// Authorization comes from `teamMemberships`, mirroring `isTeamCoach` in
/// firestore.rules. The legacy `users.teamId`/`users.role` mirror only
/// reflects the user's *active* team, so a coach whose active team is a
/// different one would be wrongly rejected if it were checked instead.
void ensureActiveCoachMembership(
  TeamMembership? actor,
  String teamId, {
  required String message,
}) {
  if (actor == null ||
      actor.teamId != teamId ||
      !actor.active ||
      !actor.isCoach) {
    throw TeamException(message);
  }
}

/// Whether the member's legacy `users/{id}` mirror describes [teamId] and
/// must be kept in sync. When the member's active team is another one, only
/// the membership is written: the mirror (and the security rule guarding it)
/// belongs to that other team.
bool shouldMirrorLegacyProfile(AppUser? member, String teamId) {
  return member != null && member.teamId == teamId;
}

enum _JoinOutcome {
  joined,
  alreadyMember,
  unavailableTeam,
  missingProfile,
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

  /// Points the user's navigation preference at [teamId] and mirrors the
  /// legacy single-team fields (`teamId`/`role`/`teamJoinedAt`) onto the
  /// profile so old, read-only client tabs still show the active team.
  /// `activeTeamId` is a routing preference, not a membership.
  Future<void> setActiveTeam({
    required String userId,
    required String? teamId,
  }) async {
    final userReference = _firestore.collection('users').doc(userId);
    await _firestore.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userReference);
      if (!userSnapshot.exists) {
        throw const TeamException('No se pudo encontrar tu perfil.');
      }
      final update = <String, dynamic>{
        'activeTeamId': teamId,
        'schemaVersion': 2,
        'membershipWriteToken': _newWriteToken(),
      };
      if (teamId != null && teamId.isNotEmpty) {
        final membershipReference = _memberships
            .doc(teamMembershipDocId(teamId, userId));
        final membershipSnapshot = await transaction.get(membershipReference);
        if (!membershipSnapshot.exists) {
          throw const TeamException('Este equipo ya no está disponible.');
        }
        final membership = TeamMembership.fromSnapshot(membershipSnapshot);
        if (!membership.active) {
          throw const TeamException('Ya no perteneces a este equipo.');
        }
        final joinedAt =
            membership.currentPeriod?.joinedAt ?? membership.teamMembershipStartedAt;
        update.addAll(_legacyMirrorFor(membership, joinedAt: joinedAt));
      } else {
        update.addAll(_emptyLegacyMirror());
      }
      transaction.update(userReference, update);
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

  /// Adds the user to [code]'s team without disturbing their other
  /// memberships. If they previously belonged and left, the membership is
  /// reactivated; otherwise a new player membership is created. The joined
  /// team becomes the active one.
  Future<void> joinTeam({
    required String code,
    required String userId,
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
    final membershipReference = _memberships
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
      final membershipSnapshot = await transaction.get(membershipReference);
      final alreadyActive = membershipSnapshot.exists &&
          TeamMembership.fromSnapshot(membershipSnapshot).active;
      if (membershipSnapshot.exists) {
        final existing = TeamMembership.fromSnapshot(membershipSnapshot);
        if (!existing.active) {
          transaction.set(
            membershipReference,
            _existingMembershipData(
              existing,
              active: true,
              openNewPeriod: true,
            ),
          );
        }
      } else {
        transaction.set(
          membershipReference,
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

      // Already an active member of the active team: nothing to change.
      if (alreadyActive && user.activeTeamId == team.id) {
        outcome = _JoinOutcome.alreadyMember;
        return;
      }

      // Make this the active team and mirror it onto the legacy profile.
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
      outcome = alreadyActive ? _JoinOutcome.alreadyMember : _JoinOutcome.joined;
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
      case null:
        throw const TeamException(
          'No se pudo completar el alta en el equipo. Inténtalo de nuevo.',
        );
    }
  }

  /// Removes the user from [teamId] only: their membership is closed (not
  /// deleted) and, if it was the active team, another active membership is
  /// selected deterministically (or the profile is cleared when none remain).
  Future<void> leaveTeam({
    required String teamId,
    required String userId,
  }) async {
    final userReference = _firestore.collection('users').doc(userId);
    final teamReference = _firestore.collection('teams').doc(teamId);
    final membershipReference = _memberships
        .doc(teamMembershipDocId(teamId, userId));

    // Best-effort list of the user's other active memberships (queried before
    // the transaction; deterministic document-id order). Used only to reselect
    // the active team when leaving the currently-active one — the app
    // self-corrects via `activeMembershipProvider` if this is stale.
    final candidates = await _memberships
        .where('userId', isEqualTo: userId)
        .where('active', isEqualTo: true)
        .get();
    final remaining = candidates.docs
        .map(TeamMembership.fromSnapshot)
        .where((membership) => membership.teamId != teamId)
        .toList();

    await _firestore.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userReference);
      if (!userSnapshot.exists) {
        throw const TeamException('No se pudo encontrar tu perfil.');
      }
      final user = AppUser.fromSnapshot(userSnapshot);

      final teamSnapshot = await transaction.get(teamReference);
      if (teamSnapshot.exists &&
          Team.fromSnapshot(teamSnapshot).createdBy == userId) {
        throw const TeamException(
          'El propietario no puede abandonar su equipo.',
        );
      }

      final membershipSnapshot = await transaction.get(membershipReference);
      if (!membershipSnapshot.exists) {
        throw const TeamException('No perteneces a este equipo.');
      }
      final membership = TeamMembership.fromSnapshot(membershipSnapshot);
      if (!membership.active) {
        throw const TeamException('Ya no perteneces a este equipo.');
      }

      transaction.set(
        membershipReference,
        _existingMembershipData(
          membership,
          active: false,
          closeOpenPeriod: true,
        ),
      );

      final update = <String, dynamic>{
        'schemaVersion': 2,
        'membershipWriteToken': _newWriteToken(),
      };
      if (user.activeTeamId == teamId) {
        if (remaining.isEmpty) {
          update.addAll(_emptyLegacyMirror());
          update['activeTeamId'] = null;
        } else {
          final next = remaining.first;
          update.addAll(
            _legacyMirrorFor(
              next,
              joinedAt:
                  next.currentPeriod?.joinedAt ?? next.teamMembershipStartedAt,
            ),
          );
          update['activeTeamId'] = next.teamId;
        }
      }
      transaction.update(userReference, update);
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
    final actorMembershipReference = _memberships
        .doc(teamMembershipDocId(teamId, actingUserId));
    final playerReference = _firestore.collection('users').doc();
    final membershipReference = _memberships
        .doc(teamMembershipDocId(teamId, playerReference.id));

    await _firestore.runTransaction((transaction) async {
      final teamSnapshot = await transaction.get(teamReference);
      final actorSnapshot = await transaction.get(actorMembershipReference);
      if (!teamSnapshot.exists) {
        throw const TeamException('El equipo ya no existe.');
      }
      ensureActiveCoachMembership(
        actorSnapshot.exists
            ? TeamMembership.fromSnapshot(actorSnapshot)
            : null,
        teamId,
        message: 'Sólo los entrenadores pueden añadir jugadores.',
      );

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
      validate: (membership) {
        if (membership.managedByCoach && role == UserRole.admin) {
          throw const TeamException(
            'Un jugador sin cuenta no puede ser entrenador.',
          );
        }
      },
      update: (
        transaction,
        memberReference,
        membershipReference,
        membership,
        mirrorLegacyProfile,
      ) {
        transaction.set(
          membershipReference,
          _existingMembershipData(
            membership,
            role: role,
            attendancePresumption: AttendancePresumption.attending,
            attendanceHistory: const [],
          ),
        );
        if (mirrorLegacyProfile) {
          transaction.update(memberReference, {
            'role': role.firestoreValue,
            'attendanceDefaultStatus':
                AttendancePresumption.attending.firestoreValue,
            'attendanceDefaultHistory': [],
            'membershipWriteToken': _newWriteToken(),
          });
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
        membership,
        mirrorLegacyProfile,
      ) {
        if (membership.managedByCoach) {
          if (mirrorLegacyProfile) {
            transaction.delete(memberReference);
          }
          transaction.delete(membershipReference);
          return;
        }
        transaction.set(
          membershipReference,
          _existingMembershipData(
            membership,
            active: false,
            closeOpenPeriod: true,
          ),
        );
        if (mirrorLegacyProfile) {
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
      validate: (membership) {
        if (membership.isCoach) {
          throw const TeamException(
            'La presunción de asistencia solo se aplica a jugadores.',
          );
        }
      },
      update: (
        transaction,
        memberReference,
        membershipReference,
        membership,
        mirrorLegacyProfile,
      ) {
        final effectiveFrom = DateTime.now();
        transaction.set(
          membershipReference,
          _existingMembershipData(
            membership,
            attendancePresumption: value,
            attendanceHistory: [
              ...membership.attendancePresumptionHistory,
              AttendancePresumptionChange(
                value: value,
                effectiveFrom: effectiveFrom,
              ),
            ],
          ),
        );
        if (mirrorLegacyProfile) {
          transaction.update(memberReference, {
            'attendanceDefaultStatus': value.firestoreValue,
            'attendanceDefaultHistory': FieldValue.arrayUnion([
              {
                'status': value.firestoreValue,
                'effectiveFrom': Timestamp.fromDate(effectiveFrom),
              },
            ]),
            'membershipWriteToken': _newWriteToken(),
          });
        }
      },
    );
  }

  /// Runs a coach action on [memberId]'s membership of [teamId].
  ///
  /// Both the acting coach and the target are resolved from
  /// `teamMemberships`, never from the legacy `users` mirror, so the action
  /// works regardless of which team either of them has active. The member's
  /// `users/{id}` mirror is only rewritten when it describes [teamId]
  /// (see [shouldMirrorLegacyProfile]).
  Future<void> _manageMember({
    required String teamId,
    required String memberId,
    required String actingUserId,
    required void Function(
      Transaction transaction,
      DocumentReference<Map<String, dynamic>> memberReference,
      DocumentReference<Map<String, dynamic>> membershipReference,
      TeamMembership membership,
      bool mirrorLegacyProfile,
    )
    update,
    void Function(TeamMembership membership)? validate,
  }) async {
    if (memberId == actingUserId) {
      throw const TeamException(
        'No puedes cambiar tu propio acceso desde esta pantalla.',
      );
    }

    final teamReference = _firestore.collection('teams').doc(teamId);
    final actorMembershipReference = _memberships
        .doc(teamMembershipDocId(teamId, actingUserId));
    final memberReference = _firestore.collection('users').doc(memberId);
    final membershipReference = _memberships
        .doc(teamMembershipDocId(teamId, memberId));

    // Read outside the transaction: the rules only let a coach read a
    // member's profile while it points at a team they belong to, so a member
    // whose active team is another one is unreadable (and must not be
    // mirrored). If the member switches teams before commit, the guarded
    // profile write is rejected and the transaction fails cleanly.
    final mirrorLegacyProfile = shouldMirrorLegacyProfile(
      await _readProfileIfVisible(memberReference),
      teamId,
    );

    await _firestore.runTransaction((transaction) async {
      final teamSnapshot = await transaction.get(teamReference);
      final actorSnapshot = await transaction.get(actorMembershipReference);
      final membershipSnapshot = await transaction.get(membershipReference);

      if (!teamSnapshot.exists) {
        throw const TeamException('El equipo ya no existe.');
      }
      ensureActiveCoachMembership(
        actorSnapshot.exists
            ? TeamMembership.fromSnapshot(actorSnapshot)
            : null,
        teamId,
        message: 'Sólo los entrenadores pueden administrar el equipo.',
      );
      if (!membershipSnapshot.exists) {
        throw const TeamException('Este miembro ya no está disponible.');
      }
      final membership = TeamMembership.fromSnapshot(membershipSnapshot);
      if (!membership.active) {
        throw const TeamException('Este miembro ya no pertenece al equipo.');
      }
      final team = Team.fromSnapshot(teamSnapshot);
      if (team.createdBy == memberId) {
        throw const TeamException(
          'El propietario del equipo debe seguir siendo entrenador.',
        );
      }

      validate?.call(membership);
      update(
        transaction,
        memberReference,
        membershipReference,
        membership,
        mirrorLegacyProfile,
      );
    });
  }

  Future<AppUser?> _readProfileIfVisible(
    DocumentReference<Map<String, dynamic>> reference,
  ) async {
    try {
      final snapshot = await reference.get();
      return snapshot.exists ? AppUser.fromSnapshot(snapshot) : null;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return null;
      }
      rethrow;
    }
  }

  // --- Write helpers ------------------------------------------------------

  String _newWriteToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Map<String, dynamic> _legacyMirrorFor(
    TeamMembership membership, {
    DateTime? joinedAt,
  }) {
    return {
      'teamId': membership.teamId,
      'teamJoinedAt': joinedAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(joinedAt),
      'role': membership.role.firestoreValue,
      'attendanceDefaultStatus':
          membership.attendancePresumption.firestoreValue,
      'attendanceDefaultHistory': _historyToWrite(
        membership.attendancePresumptionHistory,
      ),
    };
  }

  Map<String, dynamic> _emptyLegacyMirror() {
    return {
      'teamId': null,
      'teamJoinedAt': null,
      'role': UserRole.player.firestoreValue,
      'attendanceDefaultStatus':
          AttendancePresumption.attending.firestoreValue,
      'attendanceDefaultHistory': [],
    };
  }

  Map<String, dynamic> _openPeriod() {
    // Use a concrete client-side timestamp here: the web SDK cannot serialize a
    // `FieldValue.serverTimestamp()` sentinel nested inside `membershipPeriods`.
    return {'joinedAt': Timestamp.now(), 'leftAt': null};
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
