import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/app_user.dart';
import 'models/team_session.dart';
import 'repositories/attendance_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/session_repository.dart';
import 'repositories/team_repository.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);
final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(firebaseAuthProvider),
    ref.watch(firestoreProvider),
  ),
);
final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) => TeamRepository(ref.watch(firestoreProvider)),
);
final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(ref.watch(firestoreProvider)),
);
final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(ref.watch(firestoreProvider)),
);

final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);
final googleRedirectResultProvider = FutureProvider<void>(
  (ref) => ref.watch(authRepositoryProvider).completeGoogleSignInRedirect(),
);
final userProfileProvider = StreamProvider.family<AppUser?, String>(
  (ref, userId) => ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(userId)
      .snapshots()
      .map(
        (snapshot) => snapshot.exists ? AppUser.fromSnapshot(snapshot) : null,
      ),
);
final teamProvider = StreamProvider.family<Team?, String>(
  (ref, teamId) => ref.watch(teamRepositoryProvider).watchTeam(teamId),
);
final teamInvitationNameProvider = FutureProvider.family<String?, String>(
  (ref, code) => ref.watch(teamRepositoryProvider).findPublicTeamName(code),
);
final teamSessionsProvider = StreamProvider.family<List<TeamSession>, String>(
  (ref, teamId) => ref.watch(sessionRepositoryProvider).watchSessions(teamId),
);
