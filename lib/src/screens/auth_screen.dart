import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../repositories/auth_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_notification.dart';
import '../widgets/app_widgets.dart';

const _googleSignInEnabled = false;

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({this.invitationCode, super.key});

  final String? invitationCode;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _registering = false;
  bool _busy = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    await _runAuthAction((repository) async {
      if (_registering) {
        await repository.register(
          fullName: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await repository.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
    });
  }

  Future<void> _signInWithGoogle() {
    return _runAuthAction((repository) => repository.signInWithGoogle());
  }

  Future<void> _runAuthAction(
    Future<void> Function(AuthRepository repository) action,
  ) async {
    setState(() => _busy = true);
    try {
      await action(ref.read(authRepositoryProvider));
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        _showMessage(authErrorMessage(error));
      }
    } on FirebaseException {
      if (mounted) {
        _showMessage(
          'No se pudo guardar tu cuenta. Comprueba tu conexión e inténtalo '
          'de nuevo.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _showPasswordResetDialog() async {
    final dialogFormKey = GlobalKey<FormState>();
    final dialogEmailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recuperar contraseña'),
        content: Form(
          key: dialogFormKey,
          child: TextFormField(
            controller: dialogEmailController,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Correo electrónico',
              prefixIcon: Icon(Icons.mail_outline),
              helperText: 'Te enviaremos un enlace para crear otra contraseña.',
            ),
            validator: (value) {
              final candidate = value?.trim() ?? '';
              return candidate.contains('@')
                  ? null
                  : 'Escribe un correo válido.';
            },
            onFieldSubmitted: (_) {
              if (dialogFormKey.currentState!.validate()) {
                Navigator.of(
                  dialogContext,
                ).pop(dialogEmailController.text.trim());
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (dialogFormKey.currentState!.validate()) {
                Navigator.of(
                  dialogContext,
                ).pop(dialogEmailController.text.trim());
              }
            },
            child: const Text('Enviar enlace'),
          ),
        ],
      ),
    );
    dialogEmailController.dispose();
    if (email == null || !mounted) {
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordResetEmail(email: email);
      if (mounted) {
        _showPasswordResetConfirmation();
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.code == 'user-not-found') {
        _showPasswordResetConfirmation();
      } else {
        _showMessage(authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showPasswordResetConfirmation() {
    _showMessage(
      'Si existe una cuenta con ese correo, recibirás un enlace para cambiar '
      'la contraseña.',
      type: AppNotificationType.success,
    );
  }

  void _showMessage(
    String message, {
    AppNotificationType type = AppNotificationType.error,
  }) {
    showAppNotification(context, message: message, type: type);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppPageBody(
        maxWidth: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 36),
            Align(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Mi Asistencia',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Tu equipo, tus sesiones y tu disponibilidad en un solo lugar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey.shade600, height: 1.4),
            ),
            const SizedBox(height: 28),
            if (widget.invitationCode case final code?) ...[
              _InvitationNotice(code: code),
              const SizedBox(height: 16),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _registering ? 'Crear cuenta' : 'Iniciar sesión',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 20),
                      if (_registering) ...[
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(
                            labelText: 'Nombre completo',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) =>
                              value == null || value.trim().length < 2
                              ? 'Escribe tu nombre completo.'
                              : null,
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          return email.contains('@')
                              ? null
                              : 'Escribe un correo válido.';
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        autofillHints: _registering
                            ? const [AutofillHints.newPassword]
                            : const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Mostrar contraseña'
                                : 'Ocultar contraseña',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        onFieldSubmitted: (_) => _busy ? null : _submit(),
                        validator: (value) => value == null || value.length < 6
                            ? 'Usa al menos 6 caracteres.'
                            : null,
                      ),
                      if (!_registering)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _busy ? null : _showPasswordResetDialog,
                            child: const Text('He olvidado mi contraseña'),
                          ),
                        )
                      else
                        const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_registering ? 'Crear mi cuenta' : 'Entrar'),
                      ),
                      if (_googleSignInEnabled) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'o',
                                style: TextStyle(
                                  color: Colors.blueGrey.shade500,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _signInWithGoogle,
                          icon: const Icon(Icons.account_circle_outlined),
                          label: const Text('Continuar con Google'),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () =>
                                  setState(() => _registering = !_registering),
                        child: Text(
                          _registering
                              ? 'Ya tengo una cuenta'
                              : 'Quiero crear una cuenta',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({
    required this.firebaseUser,
    this.invitationCode,
    super.key,
  });

  final User firebaseUser;
  final String? invitationCode;

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  late final TextEditingController _nameController;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.firebaseUser.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameController.text.trim().length < 2) {
      showAppNotification(
        context,
        message: 'Escribe tu nombre completo.',
        type: AppNotificationType.warning,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .createProfile(
            user: widget.firebaseUser,
            fullName: _nameController.text,
          );
    } on FirebaseException {
      if (mounted) {
        showAppNotification(
          context,
          message: 'No se pudo guardar tu perfil.',
          type: AppNotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('Salir'),
          ),
        ],
      ),
      body: AppPageBody(
        maxWidth: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Completa tu perfil',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Necesitamos tu nombre para que el equipo pueda reconocerte.',
            ),
            if (widget.invitationCode case final code?) ...[
              const SizedBox(height: 16),
              _InvitationNotice(code: code),
            ],
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Guardando…' : 'Continuar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitationNotice extends ConsumerWidget {
  const _InvitationNotice({required this.code});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamName = ref.watch(teamInvitationNameProvider(code));
    final invitationText = teamName.when(
      loading: () => 'Buscando el equipo de la invitación…',
      error: (error, stackTrace) =>
          'Has recibido una invitación. Inicia sesión o crea una cuenta para '
          'continuar.',
      data: (name) => name == null
          ? 'Has recibido una invitación. Inicia sesión o crea una cuenta '
                'para continuar.'
          : 'Te han invitado a unirte a $name. Inicia sesión o crea una '
                'cuenta y te uniremos automáticamente.',
    );
    return Container(
      key: const ValueKey('pending-team-invitation'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.group_add_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              invitationText,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
