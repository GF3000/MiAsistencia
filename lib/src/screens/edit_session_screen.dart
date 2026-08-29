import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/team_session.dart';
import '../providers.dart';
import '../widgets/app_notification.dart';
import '../widgets/app_widgets.dart';
import '../widgets/async_state_view.dart';

class EditSessionScreen extends ConsumerWidget {
  const EditSessionScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(currentMembershipProvider);
    if (membership == null) {
      return const AppLoadingView();
    }
    final sessionsState = ref.watch(teamSessionsProvider(membership.teamId));
    return sessionsState.when(
      loading: () => const AppLoadingView(),
      error: (error, stackTrace) => AppErrorView(
        message: 'No se pudo cargar la sesión.',
        onRetry: () => ref.invalidate(teamSessionsProvider(membership.teamId)),
      ),
      data: (sessions) {
        TeamSession? session;
        for (final candidate in sessions) {
          if (candidate.id == sessionId) {
            session = candidate;
            break;
          }
        }
        if (session == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('La sesión ya no existe.')),
          );
        }
        return _EditSessionForm(session: session);
      },
    );
  }
}

class _EditSessionForm extends ConsumerStatefulWidget {
  const _EditSessionForm({required this.session});

  final TeamSession session;

  @override
  ConsumerState<_EditSessionForm> createState() => _EditSessionFormState();
}

class _EditSessionFormState extends ConsumerState<_EditSessionForm> {
  late final TextEditingController _titleController;
  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  bool _busy = false;
  bool _canPop = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.session.title);
    _date = DateUtils.dateOnly(widget.session.startTime);
    _startTime = TimeOfDay.fromDateTime(widget.session.startTime);
    _endTime = TimeOfDay.fromDateTime(widget.session.endTime);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (selected != null) {
      setState(() => _date = selected);
    }
  }

  Future<void> _selectTime({required bool start}) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
    );
    if (selected != null) {
      setState(() {
        if (start) {
          _startTime = selected;
        } else {
          _endTime = selected;
        }
      });
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showWarning('Escribe un título para la sesión.');
      return;
    }
    final startTime = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _startTime.hour,
      _startTime.minute,
    );
    final endTime = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _endTime.hour,
      _endTime.minute,
    );
    if (!endTime.isAfter(startTime)) {
      _showWarning('La hora de fin debe ser posterior a la de inicio.');
      return;
    }

    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(sessionRepositoryProvider)
          .updateSession(
            session: widget.session,
            title: title,
            startTime: startTime,
            endTime: endTime,
          );
      if (mounted) {
        context.pop(updated);
      }
    } on FirebaseException {
      if (mounted) {
        showAppNotification(
          context,
          message: 'No se pudo actualizar la sesión.',
          type: AppNotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showWarning(String message) {
    showAppNotification(
      context,
      message: message,
      type: AppNotificationType.warning,
    );
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Descartar cambios'),
        content: const Text('Los cambios que has hecho se perderán.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => _canPop = true);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
      appBar: AppBar(title: const Text('Editar sesión')),
      body: AppPageBody(
        maxWidth: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('edit-session-title'),
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Título',
                prefixIcon: Icon(Icons.sports_basketball_outlined),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    minTileHeight: 62,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Fecha'),
                    subtitle: Text(formatSpanishDate(_date)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _selectDate,
                  ),
                  const Divider(height: 1),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          minTileHeight: 62,
                          leading: const Icon(Icons.schedule_outlined),
                          title: const Text('Inicio'),
                          subtitle: Text(_startTime.format(context)),
                          onTap: () => _selectTime(start: true),
                        ),
                      ),
                      Expanded(
                        child: ListTile(
                          minTileHeight: 62,
                          title: const Text('Fin'),
                          subtitle: Text(_endTime.format(context)),
                          onTap: () => _selectTime(start: false),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (widget.session.recurrenceSeriesId != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.secondaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Solo se editará esta sesión. El resto de la serie '
                        'mantendrá su fecha y horario.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('save-session-edit'),
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_busy ? 'Guardando…' : 'Guardar cambios'),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
