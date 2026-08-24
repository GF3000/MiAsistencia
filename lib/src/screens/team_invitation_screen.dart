import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../providers.dart';
import '../repositories/team_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/async_state_view.dart';

class TeamInvitationScreen extends ConsumerStatefulWidget {
  const TeamInvitationScreen({
    required this.user,
    required this.code,
    required this.onFinished,
    super.key,
  });

  final AppUser user;
  final String code;
  final VoidCallback onFinished;

  @override
  ConsumerState<TeamInvitationScreen> createState() =>
      _TeamInvitationScreenState();
}

class _TeamInvitationScreenState extends ConsumerState<TeamInvitationScreen> {
  Team? _targetTeam;
  Team? _currentTeam;
  String? _message;
  Object? _loadError;
  bool _loading = true;
  bool _joining = false;
  bool _waitingForProfileUpdate = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_resolveInvitation);
  }

  @override
  void didUpdateWidget(TeamInvitationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_waitingForProfileUpdate &&
        _targetTeam != null &&
        widget.user.teamId == _targetTeam!.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onFinished();
        }
      });
    }
  }

  Future<void> _resolveInvitation() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _message = null;
        _loadError = null;
      });
    }

    try {
      final repository = ref.read(teamRepositoryProvider);
      final targetTeam = await repository.findTeamByCode(widget.code);
      if (!mounted) {
        return;
      }
      if (targetTeam == null) {
        setState(() {
          _loading = false;
          _message =
              'No encontramos ningún equipo con el código ${widget.code}.';
        });
        return;
      }
      if (widget.user.teamId == targetTeam.id) {
        widget.onFinished();
        return;
      }

      _targetTeam = targetTeam;
      if (!widget.user.hasTeam) {
        setState(() => _loading = false);
        await _joinTeam(allowTeamSwitch: false);
        return;
      }
      if (widget.user.isCoach) {
        setState(() {
          _loading = false;
          _message =
              'Eres entrenador de tu equipo actual. Antes de unirte a '
              '${targetTeam.name}, debes transferir su gestión.';
        });
        return;
      }

      final currentTeam = await repository.getTeam(widget.user.teamId!);
      if (!mounted) {
        return;
      }
      setState(() {
        _currentTeam = currentTeam;
        _loading = false;
      });
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = error;
        });
      }
    }
  }

  Future<void> _joinTeam({required bool allowTeamSwitch}) async {
    setState(() => _joining = true);
    try {
      await ref
          .read(teamRepositoryProvider)
          .joinTeam(
            code: widget.code,
            userId: widget.user.id,
            allowTeamSwitch: allowTeamSwitch,
          );
      if (mounted) {
        setState(() => _waitingForProfileUpdate = true);
      }
    } on TeamException catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() => _loadError = error);
      }
    } finally {
      if (mounted) {
        setState(() => _joining = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading ||
        _waitingForProfileUpdate ||
        (_targetTeam != null && !widget.user.hasTeam && _joining)) {
      return const _InvitationLoadingView();
    }
    if (_loadError != null) {
      return AppErrorView(
        message: 'No se pudo comprobar la invitación.',
        onRetry: _resolveInvitation,
      );
    }
    if (_message case final message?) {
      return InvitationMessageScreen(
        message: message,
        onContinue: widget.onFinished,
      );
    }

    if (!widget.user.hasTeam || _targetTeam == null) {
      return InvitationMessageScreen(
        message: 'No se pudo completar la invitación.',
        onContinue: widget.onFinished,
      );
    }

    return TeamSwitchPrompt(
      currentTeamName: _currentTeam?.name ?? 'tu equipo actual',
      targetTeamName: _targetTeam!.name,
      busy: _joining,
      onCancel: widget.onFinished,
      onConfirm: () => _joinTeam(allowTeamSwitch: true),
    );
  }
}

class TeamSwitchPrompt extends StatelessWidget {
  const TeamSwitchPrompt({
    required this.currentTeamName,
    required this.targetTeamName,
    required this.busy,
    required this.onCancel,
    required this.onConfirm,
    super.key,
  });

  final String currentTeamName;
  final String targetTeamName;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppPageBody(
        maxWidth: 500,
        child: Card(
          key: const ValueKey('team-switch-prompt'),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.move_up_rounded,
                    color: AppTheme.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '¿Cambiar de equipo?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'Actualmente perteneces a $currentTeamName. ¿Quieres salirte '
                  'para unirte a $targetTeamName?',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: busy ? null : onCancel,
                      child: const Text('Mantener mi equipo'),
                    ),
                    FilledButton(
                      onPressed: busy ? null : onConfirm,
                      child: Text(busy ? 'Cambiando…' : 'Cambiar de equipo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InvitationMessageScreen extends StatelessWidget {
  const InvitationMessageScreen({
    required this.message,
    required this.onContinue,
    super.key,
  });

  final String message;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppPageBody(
        maxWidth: 500,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'No se puede completar la invitación',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onContinue,
                  child: const Text('Continuar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InvitationLoadingView extends StatelessWidget {
  const _InvitationLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Comprobando la invitación…'),
          ],
        ),
      ),
    );
  }
}
