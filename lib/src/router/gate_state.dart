import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../repositories/auth_repository.dart';

/// Synchronous snapshot of where the signed-in user currently sits in the
/// onboarding flow, used by the router to redirect to the right screen.
sealed class GateState {
  const GateState();
}

class GateChecking extends GateState {
  const GateChecking();
}

class GateError extends GateState {
  const GateError(this.message);

  final String message;
}

class GateSignedOut extends GateState {
  const GateSignedOut();
}

class GateNeedsProfile extends GateState {
  const GateNeedsProfile();
}

class GateOnboarding extends GateState {
  const GateOnboarding();
}

class GateReady extends GateState {
  const GateReady();
}

final gateStateProvider = Provider<GateState>((ref) {
  final redirect = ref.watch(googleRedirectResultProvider);
  if (redirect.isLoading) {
    return const GateChecking();
  }
  if (redirect.hasError) {
    final error = redirect.error;
    return GateError(
      error is FirebaseAuthException
          ? authErrorMessage(error)
          : 'No se pudo completar el acceso con Google.',
    );
  }

  final auth = ref.watch(authStateProvider);
  if (auth.isLoading) {
    return const GateChecking();
  }
  if (auth.hasError) {
    return const GateError('No se pudo comprobar tu sesión.');
  }
  final user = auth.value;
  if (user == null) {
    return const GateSignedOut();
  }

  final profile = ref.watch(userProfileProvider(user.uid));
  if (profile.isLoading) {
    return const GateChecking();
  }
  if (profile.hasError) {
    return const GateError('No se pudo cargar tu perfil.');
  }
  final appUser = profile.value;
  if (appUser == null) {
    return const GateNeedsProfile();
  }

  final membership = ref.watch(activeMembershipProvider(appUser.id));
  if (membership.isLoading) {
    return const GateChecking();
  }
  if (membership.hasError) {
    return const GateError('No se pudo cargar tu equipo.');
  }
  if (membership.value == null) {
    return const GateOnboarding();
  }
  return const GateReady();
});
