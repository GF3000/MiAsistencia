import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../models/app_user.dart';
import '../providers.dart';
import '../repositories/team_repository.dart';
import '../widgets/app_notification.dart';
import '../widgets/app_widgets.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({required this.user, super.key});

  final AppUser user;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _teamNameController = TextEditingController();
  final _teamCodeController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _teamNameController.dispose();
    _teamCodeController.dispose();
    super.dispose();
  }

  Future<void> _createTeam() async {
    if (_teamNameController.text.trim().length < 2) {
      _showMessage(
        'Escribe el nombre del equipo.',
        type: AppNotificationType.warning,
      );
      return;
    }
    await _runTeamAction(
      () => ref
          .read(teamRepositoryProvider)
          .createTeam(name: _teamNameController.text, userId: widget.user.id),
    );
  }

  Future<void> _joinTeam() async {
    if (_teamCodeController.text.trim().length != 6) {
      _showMessage(
        'El código debe tener 6 caracteres.',
        type: AppNotificationType.warning,
      );
      return;
    }
    await _runTeamAction(
      () => ref
          .read(teamRepositoryProvider)
          .joinTeam(code: _teamCodeController.text, userId: widget.user.id),
    );
  }

  Future<void> _runTeamAction(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on TeamException catch (error) {
      _showMessage(error.message);
    } on FirebaseException {
      _showMessage('No se pudo actualizar el equipo. Inténtalo de nuevo.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showMessage(
    String message, {
    AppNotificationType type = AppNotificationType.error,
  }) {
    if (mounted) {
      showAppNotification(context, message: message, type: type);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configura tu equipo'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: AppPageBody(
        maxWidth: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '¡Hola, ${widget.user.fullName.split(' ').first}!',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Crea un equipo si eres entrenador o únete con el código que te '
              'han compartido.',
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Crear equipo'),
                  Tab(text: 'Unirme'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 330,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _CreateTeamPanel(
                    controller: _teamNameController,
                    busy: _busy,
                    onSubmit: _createTeam,
                  ),
                  _JoinTeamPanel(
                    controller: _teamCodeController,
                    busy: _busy,
                    onSubmit: _joinTeam,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateTeamPanel extends StatelessWidget {
  const _CreateTeamPanel({
    required this.controller,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.add_business_outlined, size: 42),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre del equipo',
                hintText: 'Ej. Halcones Senior',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : onSubmit,
              child: Text(busy ? 'Creando…' : 'Crear equipo'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Recibirás un código de 6 caracteres para invitar a los '
              'jugadores.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinTeamPanel extends StatelessWidget {
  const _JoinTeamPanel({
    required this.controller,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.group_add_outlined, size: 42),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                _UpperCaseTextFormatter(),
              ],
              style: const TextStyle(
                letterSpacing: 8,
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
              decoration: const InputDecoration(
                labelText: 'Código del equipo',
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : onSubmit,
              child: Text(busy ? 'Buscando…' : 'Unirme al equipo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
