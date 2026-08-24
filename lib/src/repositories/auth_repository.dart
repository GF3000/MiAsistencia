import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthRepository {
  AuthRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<void> completeGoogleSignInRedirect() async {
    await _auth.getRedirectResult();
  }

  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signInWithGoogle() async {
    await _auth.signInWithPopup(GoogleAuthProvider());
  }

  Future<void> sendPasswordResetEmail({required String email}) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'missing-user',
        message: 'No se pudo crear el usuario.',
      );
    }
    await user.updateDisplayName(fullName.trim());
    await createProfile(user: user, fullName: fullName);
  }

  Future<void> createProfile({required User user, required String fullName}) {
    return _firestore.collection('users').doc(user.uid).set({
      'email': user.email ?? '',
      'fullName': fullName.trim(),
      'role': 'player',
      'teamId': null,
      'teamJoinedAt': null,
      'active': true,
      'managedByCoach': false,
      'attendanceDefaultStatus': 'attending',
      'attendanceDefaultHistory': [],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> signOut() => _auth.signOut();
}

String authErrorMessage(FirebaseAuthException error) {
  return switch (error.code) {
    'invalid-email' => 'El correo no es válido.',
    'user-disabled' => 'Esta cuenta está desactivada.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' => 'El correo o la contraseña no son correctos.',
    'email-already-in-use' => 'Ya existe una cuenta con ese correo.',
    'weak-password' => 'La contraseña debe tener al menos 6 caracteres.',
    'account-exists-with-different-credential' =>
      'Ya existe una cuenta con ese correo. Accede con el método que usaste '
          'originalmente.',
    'operation-not-allowed' =>
      'Este método de acceso todavía no está habilitado.',
    'unauthorized-domain' =>
      'Este dominio no está autorizado para acceder con Google.',
    'web-storage-unsupported' =>
      'El navegador está bloqueando el almacenamiento necesario para acceder '
          'con Google.',
    'operation-not-supported-in-this-environment' =>
      'Este navegador no permite completar el acceso con Google.',
    'popup-blocked' =>
      'El navegador ha bloqueado la ventana de Google. Permite las ventanas '
          'emergentes e inténtalo de nuevo.',
    'popup-closed-by-user' ||
    'cancelled-popup-request' => 'Se ha cancelado el acceso con Google.',
    'network-request-failed' =>
      'No hay conexión. Comprueba tu red e inténtalo de nuevo.',
    'too-many-requests' =>
      'Demasiados intentos. Espera unos minutos y vuelve a intentarlo.',
    _ => 'No se pudo completar el acceso. Inténtalo de nuevo.',
  };
}
