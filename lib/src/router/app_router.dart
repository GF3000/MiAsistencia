import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/team_session.dart';
import '../providers.dart';
import '../repositories/team_repository.dart';
import '../screens/auth_screen.dart';
import '../screens/batch_attendance_screen.dart';
import '../screens/batch_edit_sessions_screen.dart';
import '../screens/create_session_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/edit_session_screen.dart';
import '../screens/manage_team_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/session_detail_screen.dart';
import '../screens/team_invitation_screen.dart';
import '../widgets/async_state_view.dart';
import 'gate_state.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(gateStateProvider, (previous, next) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) =>
        _redirectForGate(ref.read(gateStateProvider), state),
    routes: [
      GoRoute(
        path: '/loading',
        builder: (context, state) => const AppLoadingView(),
      ),
      GoRoute(
        path: '/error',
        builder: (context, state) => const _GateErrorScreen(),
      ),
      GoRoute(
        path: '/auth',
        builder: (context, state) => AuthScreen(
          invitationCode: state.uri.queryParameters['join'],
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => ProfileSetupScreen(
          invitationCode: state.uri.queryParameters['join'],
        ),
      ),
      GoRoute(
        path: '/invite/:code',
        builder: (context, state) =>
            TeamInvitationScreen(code: state.pathParameters['code']!),
      ),
      GoRoute(
        path: '/invite-invalid',
        builder: (context, state) => InvitationMessageScreen(
          message: 'El enlace de invitación no contiene un código válido.',
          onContinue: () => context.go('/'),
        ),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => OnboardingScreen(
          initialTab: int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/team/manage',
        builder: (context, state) => const ManageTeamScreen(),
      ),
      GoRoute(
        path: '/sessions/new',
        builder: (context, state) =>
            CreateSessionScreen(initialDate: state.extra as DateTime?),
      ),
      GoRoute(
        path: '/sessions/batch-edit',
        builder: (context, state) => BatchEditSessionsScreen(
          sessions: state.extra as List<TeamSession>,
        ),
      ),
      GoRoute(
        path: '/sessions/batch-attendance',
        builder: (context, state) => BatchAttendanceScreen(
          sessions: state.extra as List<TeamSession>,
        ),
      ),
      GoRoute(
        path: '/sessions/:id',
        builder: (context, state) =>
            SessionDetailScreen(sessionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/sessions/:id/edit',
        builder: (context, state) =>
            EditSessionScreen(sessionId: state.pathParameters['id']!),
      ),
    ],
  );
});

String? _redirectForGate(GateState gate, GoRouterState state) {
  final location = state.uri.path;
  final rawJoin = state.uri.queryParameters['join'];
  final join = normalizeTeamCode(rawJoin);

  switch (gate) {
    case GateChecking():
      return location == '/loading' ? null : '/loading';
    case GateError():
      return location == '/error' ? null : '/error';
    case GateSignedOut():
      if (location == '/auth') {
        return null;
      }
      return join != null ? '/auth?join=$join' : '/auth';
    case GateNeedsProfile():
      if (location == '/profile') {
        return null;
      }
      return join != null ? '/profile?join=$join' : '/profile';
    case GateOnboarding():
    case GateReady():
      if (rawJoin != null && join == null) {
        return location == '/invite-invalid' ? null : '/invite-invalid';
      }
      if (join != null) {
        return location == '/invite/$join' ? null : '/invite/$join';
      }
      if (location == '/invite-invalid' || location.startsWith('/invite/')) {
        return null;
      }
      if (location == '/onboarding') {
        return null;
      }
      if (gate is GateOnboarding) {
        return '/onboarding';
      }
      if (location == '/' ||
          location == '/team/manage' ||
          location.startsWith('/sessions')) {
        return null;
      }
      return '/';
  }
}

class _GateErrorScreen extends ConsumerWidget {
  const _GateErrorScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(gateStateProvider);
    final message = gate is GateError ? gate.message : 'Se ha producido un error.';
    return AppErrorView(
      message: message,
      onRetry: () {
        ref.invalidate(googleRedirectResultProvider);
        ref.invalidate(authStateProvider);
        ref.invalidate(userProfileProvider);
        ref.invalidate(activeMembershipProvider);
      },
    );
  }
}
