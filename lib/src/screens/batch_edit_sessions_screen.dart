import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/team_session.dart';
import '../providers.dart';
import '../widgets/app_notification.dart';
import '../widgets/app_widgets.dart';

class BatchEditSessionsScreen extends ConsumerStatefulWidget {
  const BatchEditSessionsScreen({required this.sessions, super.key});

  final List<TeamSession> sessions;

  @override
  ConsumerState<BatchEditSessionsScreen> createState() =>
      _BatchEditSessionsScreenState();
}

class _BatchEditSessionsScreenState
    extends ConsumerState<BatchEditSessionsScreen> {
  late final TextEditingController _titleController;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  bool _changeTitle = false;
  bool _changeTime = false;
  bool _busy = false;
  bool _canPop = false;

  @override
  void initState() {
    super.initState();
    final first = widget.sessions.first;
    final commonTitle = widget.sessions.every(
      (session) => session.title == first.title,
    );
    _titleController = TextEditingController(
      text: commonTitle ? first.title : '',
    );
    _startTime = TimeOfDay.fromDateTime(first.startTime);
    _endTime = TimeOfDay.fromDateTime(first.endTime);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
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
    if (!_changeTitle && !_changeTime) {
      _showWarning('Selecciona al menos un cambio.');
      return;
    }
    final title = _titleController.text.trim();
    if (_changeTitle && title.isEmpty) {
      _showWarning('Escribe el nuevo nombre de las sesiones.');
      return;
    }
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    if (_changeTime && endMinutes <= startMinutes) {
      _showWarning('La hora de fin debe ser posterior a la de inicio.');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(sessionRepositoryProvider)
          .updateSessions(
            sessions: widget.sessions,
            title: _changeTitle ? title : null,
            startTime: _changeTime
                ? DateTime(2000, 1, 1, _startTime.hour, _startTime.minute)
                : null,
            endTime: _changeTime
                ? DateTime(2000, 1, 1, _endTime.hour, _endTime.minute)
                : null,
          );
      if (mounted) {
        context.pop(true);
      }
    } on FirebaseException {
      if (mounted) {
        showAppNotification(
          context,
          message: 'No se pudieron modificar las sesiones.',
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
      appBar: AppBar(
        title: Text('Modificar ${widget.sessions.length} sesiones'),
      ),
      body: AppPageBody(
        maxWidth: 650,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cada sesión conservará su fecha. El nombre y el '
                      'horario se aplicarán a todas las seleccionadas.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Cambiar nombre'),
                      value: _changeTitle,
                      onChanged: (value) =>
                          setState(() => _changeTitle = value),
                    ),
                    if (_changeTitle) ...[
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('batch-session-title'),
                        controller: _titleController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Nuevo nombre',
                        ),
                      ),
                    ],
                    const Divider(height: 30),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Cambiar horario'),
                      value: _changeTime,
                      onChanged: (value) => setState(() => _changeTime = value),
                    ),
                    if (_changeTime) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                side: const BorderSide(
                                  color: Color(0xFFD8E1E8),
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              title: const Text('Inicio'),
                              subtitle: Text(_startTime.format(context)),
                              onTap: () => _selectTime(start: true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                side: const BorderSide(
                                  color: Color(0xFFD8E1E8),
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              title: const Text('Fin'),
                              subtitle: Text(_endTime.format(context)),
                              onTap: () => _selectTime(start: false),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_busy ? 'Guardando…' : 'Aplicar cambios'),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
