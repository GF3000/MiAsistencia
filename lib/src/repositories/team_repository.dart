import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';

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

  Stream<Team?> watchTeam(String teamId) {
    return _firestore
        .collection('teams')
        .doc(teamId)
        .snapshots()
        .map(
          (snapshot) => snapshot.exists ? Team.fromSnapshot(snapshot) : null,
        );
  }

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

      var collision = false;
      await _firestore.runTransaction((transaction) async {
        collision = false;
        final existingTeam = await transaction.get(teamReference);
        if (existingTeam.exists) {
          collision = true;
          return;
        }
        transaction.set(teamReference, {
          'name': name.trim(),
          'joinCode': code,
          'createdBy': userId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.set(invitationReference, {'name': name.trim()});
        transaction.update(userReference, {
          'teamId': teamReference.id,
          'teamJoinedAt': FieldValue.serverTimestamp(),
          'role': 'admin',
          'attendanceDefaultStatus': 'attending',
          'attendanceDefaultHistory': [],
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

      transaction.update(userReference, {
        'teamId': team.id,
        'teamJoinedAt': FieldValue.serverTimestamp(),
        'role': UserRole.player.firestoreValue,
        'attendanceDefaultStatus':
            AttendancePresumption.attending.firestoreValue,
        'attendanceDefaultHistory': [],
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
      transaction.update(userReference, {
        'teamId': null,
        'teamJoinedAt': null,
        'role': UserRole.player.firestoreValue,
        'attendanceDefaultStatus': 'attending',
        'attendanceDefaultHistory': [],
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
      });
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
      update: (transaction, memberReference, member) {
        transaction.update(memberReference, {
          'role': role.firestoreValue,
          if (role == UserRole.player) ...{
            'attendanceDefaultStatus': 'attending',
            'attendanceDefaultHistory': [],
          },
        });
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
      update: (transaction, memberReference, member) {
        if (member.managedByCoach) {
          transaction.delete(memberReference);
          return;
        }
        transaction.update(memberReference, {
          'teamId': null,
          'teamJoinedAt': null,
          'role': UserRole.player.firestoreValue,
          'attendanceDefaultStatus': 'attending',
          'attendanceDefaultHistory': [],
        });
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
      update: (transaction, memberReference, member) {
        transaction.update(memberReference, {
          'attendanceDefaultStatus': value.firestoreValue,
          'attendanceDefaultHistory': FieldValue.arrayUnion([
            {'status': value.firestoreValue, 'effectiveFrom': Timestamp.now()},
          ]),
        });
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
      AppUser member,
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
      update(transaction, memberReference, member);
    });
  }
}
