import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/app_user.dart';
import 'models/team_membership.dart';
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
final membershipsForUserProvider =
    StreamProvider.family<List<TeamMembership>, String>(
  (ref, userId) => ref
      .watch(teamRepositoryProvider)
      .watchMembershipsForUser(userId),
);
final teamMembersProvider = StreamProvider.family<List<TeamMembership>, String>(
  (ref, teamId) => ref.watch(teamRepositoryProvider).watchTeamMembers(teamId),
);
final membershipProvider = StreamProvider.family<
    TeamMembership?,
    ({String teamId, String memberId})>(
  (ref, key) => ref
      .watch(teamRepositoryProvider)
      .watchMembership(key.teamId, key.memberId),
);
final currentFirebaseUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).value;
});

final currentAppUserProvider = Provider<AppUser?>((ref) {
  final user = ref.watch(currentFirebaseUserProvider);
  if (user == null) {
    return null;
  }
  return ref.watch(userProfileProvider(user.uid)).value;
});

final currentMembershipProvider = Provider<TeamMembership?>((ref) {
  final appUser = ref.watch(currentAppUserProvider);
  if (appUser == null) {
    return null;
  }
  return ref.watch(activeMembershipProvider(appUser.id)).value;
});

/// Whether the "Rendimiento" KPI card on the coach's player detail screen is
/// expanded. Kept outside the screen's widget state so it survives
/// navigating between players (which replaces the screen instance).
class PlayerPerformanceCardExpandedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final playerPerformanceCardExpandedProvider =
    NotifierProvider<PlayerPerformanceCardExpandedNotifier, bool>(
      PlayerPerformanceCardExpandedNotifier.new,
    );

final activeMembershipProvider = Provider.family<AsyncValue<TeamMembership?>, String>(
  (ref, userId) {
    final memberships = ref.watch(membershipsForUserProvider(userId));
    final profile = ref.watch(userProfileProvider(userId));
    if (memberships.hasError || profile.hasError) {
      return AsyncValue.error(
        memberships.hasError ? memberships.error! : profile.error!,
        memberships.hasError
            ? memberships.stackTrace!
            : profile.stackTrace!,
      );
    }
    if (memberships.isLoading || profile.isLoading) {
      return const AsyncValue.loading();
    }
    final active = memberships.value
            ?.where((membership) => membership.active)
            .toList() ??
        const <TeamMembership>[];
    if (active.isEmpty) {
      return const AsyncValue.data(null);
    }
    final activeTeamId = profile.value?.activeTeamId;
    final resolved = active.firstWhere(
      (membership) => membership.teamId == activeTeamId,
      orElse: () => active.first,
    );
    return AsyncValue.data(resolved);
  },
);
