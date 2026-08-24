import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'screens/auth_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/team_invitation_screen.dart';
import 'repositories/auth_repository.dart';
import 'repositories/team_repository.dart';
import 'theme/app_theme.dart';
import 'widgets/async_state_view.dart';

class MiAsistenciaApp extends StatelessWidget {
  const MiAsistenciaApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi Asistencia',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home ?? const AppGate(),
    );
  }
}

class AppGate extends ConsumerStatefulWidget {
  const AppGate({this.initialJoinCode, super.key});

  final String? initialJoinCode;

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> {
  String? _pendingJoinCode;
  bool _invalidJoinCode = false;

  @override
  void initState() {
    super.initState();
    final rawCode = widget.initialJoinCode ?? Uri.base.queryParameters['join'];
    _pendingJoinCode = normalizeTeamCode(rawCode);
    _invalidJoinCode = rawCode != null && _pendingJoinCode == null;
  }

  void _consumeInvitation() {
    if (mounted) {
      setState(() {
        _pendingJoinCode = null;
        _invalidJoinCode = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_invalidJoinCode) {
      return InvitationMessageScreen(
        message: 'El enlace de invitación no contiene un código válido.',
        onContinue: _consumeInvitation,
      );
    }

    final redirectResult = ref.watch(googleRedirectResultProvider);
    return redirectResult.when(
      loading: () => const AppLoadingView(),
      error: (error, stackTrace) => AppErrorView(
        message: error is FirebaseAuthException
            ? authErrorMessage(error)
            : 'No se pudo completar el acceso con Google.',
        onRetry: () => ref.invalidate(googleRedirectResultProvider),
      ),
      data: (_) {
        final authState = ref.watch(authStateProvider);
        return authState.when(
          loading: () => const AppLoadingView(),
          error: (error, stackTrace) => AppErrorView(
            message: 'No se pudo comprobar tu sesión.',
            onRetry: () => ref.invalidate(authStateProvider),
          ),
          data: (firebaseUser) {
            if (firebaseUser == null) {
              return AuthScreen(invitationCode: _pendingJoinCode);
            }
            return _ProfileGate(
              firebaseUser: firebaseUser,
              pendingJoinCode: _pendingJoinCode,
              onInvitationConsumed: _consumeInvitation,
            );
          },
        );
      },
    );
  }
}

class _ProfileGate extends ConsumerWidget {
  const _ProfileGate({
    required this.firebaseUser,
    required this.pendingJoinCode,
    required this.onInvitationConsumed,
  });

  final User firebaseUser;
  final String? pendingJoinCode;
  final VoidCallback onInvitationConsumed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider(firebaseUser.uid));
    return profile.when(
      loading: () => const AppLoadingView(),
      error: (error, stackTrace) => AppErrorView(
        message: 'No se pudo cargar tu perfil.',
        onRetry: () => ref.invalidate(userProfileProvider(firebaseUser.uid)),
      ),
      data: (appUser) {
        if (appUser == null) {
          return ProfileSetupScreen(
            firebaseUser: firebaseUser,
            invitationCode: pendingJoinCode,
          );
        }
        if (pendingJoinCode case final code?) {
          return TeamInvitationScreen(
            user: appUser,
            code: code,
            onFinished: onInvitationConsumed,
          );
        }
        if (!appUser.hasTeam) {
          return OnboardingScreen(user: appUser);
        }
        return DashboardScreen(user: appUser);
      },
    );
  }
}
