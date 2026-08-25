import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attendance.dart';
import '../models/team_membership.dart';
import '../models/team_session.dart';
import '../providers.dart';
import '../widgets/app_notification.dart';
import '../widgets/app_widgets.dart';

Future<bool?> showBatchAttendanceEditor({
  required BuildContext context,
  required TeamRosterMember user,
  required List<TeamSession> sessions,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 700),
    builder: (context) =>
        _BatchAttendanceEditor(user: user, sessions: sessions),
  );
}

class BatchAttendanceScreen extends ConsumerStatefulWidget {
  const BatchAttendanceScreen({
    required this.user,
    required this.sessions,
    this.initiallySelectAll = false,
    super.key,
  });

  final TeamRosterMember user;
  final List<TeamSession> sessions;
  final bool initiallySelectAll;

  @override
  ConsumerState<BatchAttendanceScreen> createState() =>
      _BatchAttendanceScreenState();
}

class _BatchAttendanceScreenState extends ConsumerState<BatchAttendanceScreen> {
  final Set<String> _selectedSessionIds = {};

  List<TeamSession> get _editableSessions =>
      widget.sessions.where(canPlayerEditAttendance).toList();

  @override
  void initState() {
    super.initState();
    if (widget.initiallySelectAll) {
      _selectedSessionIds.addAll(
        widget.sessions
            .where(canPlayerEditAttendance)
            .map((session) => session.id),
      );
    }
  }

  void _selectSessions(Iterable<TeamSession> sessions) {
    setState(() {
      _selectedSessionIds
        ..clear()
        ..addAll(sessions.map((session) => session.id));
    });
  }

  Future<void> _changeAttendance() async {
    final selectedSessions = _editableSessions
        .where((session) => _selectedSessionIds.contains(session.id))
        .toList();
    if (selectedSessions.isEmpty) {
      showAppNotification(
        context,
        message: 'Selecciona al menos una sesión.',
        type: AppNotificationType.warning,
      );
      return;
    }
    final saved = await showBatchAttendanceEditor(
      context: context,
      user: widget.user,
      sessions: selectedSessions,
    );
    if (saved == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editableSessions = _editableSessions;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seleccionar varias'),
        actions: [
          TextButton(
            onPressed: () {
              if (_selectedSessionIds.length == editableSessions.length) {
                _selectSessions(const []);
              } else {
                _selectSessions(editableSessions);
              }
            },
            child: Text(
              _selectedSessionIds.length == editableSessions.length
                  ? 'Ninguna'
                  : 'Todas',
            ),
          ),
        ],
      ),
      body: AppPageBody(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Selecciona por período',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ActionChip(
                      key: const ValueKey('select-next-week'),
                      avatar: const Icon(Icons.date_range_outlined),
                      label: const Text('Próximos 7 días'),
                      onPressed: () => _selectSessions(
                        sessionsInNextDays(editableSessions, days: 7),
                      ),
                    ),
                    ActionChip(
                      key: const ValueKey('select-next-month'),
                      avatar: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Próximos 30 días'),
                      onPressed: () => _selectSessions(
                        sessionsInNextDays(editableSessions, days: 30),
                      ),
                    ),
                    PopupMenuButton<int>(
                      key: const ValueKey('select-weekday'),
                      tooltip: 'Seleccionar por día de la semana',
                      onSelected: (weekday) => _selectSessions(
                        sessionsOnWeekday(editableSessions, weekday),
                      ),
                      itemBuilder: (context) => List.generate(
                        7,
                        (index) => PopupMenuItem(
                          value: index + 1,
                          child: Text(_weekdayName(index + 1)),
                        ),
                      ),
                      child: const Chip(
                        avatar: Icon(Icons.today_outlined),
                        label: Text('Día de la semana'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sesiones',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  '${_selectedSessionIds.length} seleccionadas',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (editableSessions.isEmpty)
              const EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'No hay sesiones disponibles',
                message:
                    'Solo se puede actualizar la asistencia de sesiones que '
                    'no hayan finalizado.',
              )
            else
              Card(
                child: Column(
                  children: editableSessions.map((session) {
                    final selected = _selectedSessionIds.contains(session.id);
                    return CheckboxListTile(
                      value: selected,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(session.title),
                      subtitle: Text(
                        '${formatSpanishDate(session.startTime)} · '
                        '${formatTime(context, session.startTime)}',
                      ),
                      onChanged: (value) => setState(() {
                        value == true
                            ? _selectedSessionIds.add(session.id)
                            : _selectedSessionIds.remove(session.id);
                      }),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: editableSessions.isEmpty
          ? null
          : _BatchAttendanceBottomBar(
              count: _selectedSessionIds.length,
              onClear: () => _selectSessions(const []),
              onChangeAttendance: _selectedSessionIds.isEmpty
                  ? null
                  : _changeAttendance,
            ),
    );
  }
}

class _BatchAttendanceBottomBar extends StatelessWidget {
  const _BatchAttendanceBottomBar({
    required this.count,
    required this.onClear,
    required this.onChangeAttendance,
  });

  final int count;
  final VoidCallback onClear;
  final VoidCallback? onChangeAttendance;

  @override
  Widget build(BuildContext context) {
    final countLabel = count == 1
        ? '1 sesión seleccionada'
        : '$count sesiones seleccionadas';
    return Material(
      key: const ValueKey('batch-attendance-bottom-bar'),
      color: Colors.white,
      elevation: 18,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final countAndClear = Row(
                  children: [
                    Expanded(
                      child: Text(
                        countLabel,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('clear-batch-attendance-selection'),
                      onPressed: count == 0 ? null : onClear,
                      child: const Text('Limpiar'),
                    ),
                  ],
                );
                final changeButton = FilledButton.icon(
                  key: const ValueKey('change-batch-attendance'),
                  onPressed: onChangeAttendance,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Cambiar asistencia'),
                );

                if (constraints.maxWidth < 600) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      countAndClear,
                      const SizedBox(height: 6),
                      changeButton,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: countAndClear),
                    const SizedBox(width: 12),
                    changeButton,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _BatchAttendanceEditor extends ConsumerStatefulWidget {
  const _BatchAttendanceEditor({required this.user, required this.sessions});

  final TeamRosterMember user;
  final List<TeamSession> sessions;

  @override
  ConsumerState<_BatchAttendanceEditor> createState() =>
      _BatchAttendanceEditorState();
}

class _BatchAttendanceEditorState
    extends ConsumerState<_BatchAttendanceEditor> {
  final _noteController = TextEditingController();
  AttendanceStatus _status = AttendanceStatus.absent;
  bool _busy = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(attendanceRepositoryProvider)
          .saveBatchAttendance(
            sessionIds: widget.sessions.map((session) => session.id),
            userId: widget.user.id,
            status: _status,
            note: _noteController.text,
          );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        showAppNotification(
          context,
          message: error.code == 'permission-denied'
              ? 'No tienes permiso para modificar una o más sesiones. '
                    'Un entrenador puede haber registrado una incidencia.'
              : 'No se pudo aplicar la actualización.',
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
    final sessionCountLabel =
        '${widget.sessions.length} '
        '${widget.sessions.length == 1 ? 'sesión' : 'sesiones'}';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade200,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Estado y nota',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'El cambio se aplicará a $sessionCountLabel.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Selecciona el estado',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AttendanceStatus.playerOptions
                  .map(
                    (status) => ChoiceChip(
                      selected: _status == status,
                      avatar: Icon(status.icon, size: 18, color: status.color),
                      label: Text(status.playerLabel),
                      onSelected: (_) => setState(() => _status = status),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _noteController,
              maxLength: 180,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Nota opcional',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('apply-batch-attendance'),
              onPressed: _busy ? null : _apply,
              icon: const Icon(Icons.done_all),
              label: Text(
                _busy ? 'Actualizando…' : 'Aplicar a $sessionCountLabel',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _weekdayName(int weekday) {
  return const {
    DateTime.monday: 'Lunes',
    DateTime.tuesday: 'Martes',
    DateTime.wednesday: 'Miércoles',
    DateTime.thursday: 'Jueves',
    DateTime.friday: 'Viernes',
    DateTime.saturday: 'Sábado',
    DateTime.sunday: 'Domingo',
  }[weekday]!;
}
