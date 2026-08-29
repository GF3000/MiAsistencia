import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/app_user.dart';
import '../models/attendance.dart';
import '../models/team_membership.dart';
import '../models/team_session.dart';
import '../providers.dart';
import '../widgets/app_notification.dart';
import '../widgets/app_widgets.dart';
import '../widgets/async_state_view.dart';
import '../widgets/attendance_editor.dart';

class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  @override
  Widget build(BuildContext context) {
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
          if (candidate.id == widget.sessionId) {
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
        return _buildContent(session, membership, sessions);
      },
    );
  }

  Widget _buildContent(
    TeamSession session,
    TeamRosterMember currentUser,
    List<TeamSession> sessions,
  ) {
    final timeline = buildSessionTimelinePosition(
      sessions: sessions,
      currentSessionId: session.id,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de la sesión'),
        actions: [
          if (currentUser.isCoach)
            IconButton(
              tooltip: 'Editar sesión',
              onPressed: () => _editSession(session),
              icon: const Icon(Icons.edit_outlined),
            ),
          if (currentUser.isCoach)
            IconButton(
              tooltip: 'Eliminar sesión',
              onPressed: () => _confirmDelete(session),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: AppPageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SessionTimelineNavigation(
              timeline: timeline,
              onPrevious: timeline.previous == null
                  ? null
                  : () => _openSession(timeline.previous!),
              onNext: timeline.next == null
                  ? null
                  : () => _openSession(timeline.next!),
            ),
            const SizedBox(height: 12),
            _SessionHeader(session: session),
            const SizedBox(height: 22),
            if (currentUser.isCoach)
              _CoachAttendancePanel(session: session, currentUser: currentUser)
            else
              _PlayerAttendancePanel(
                session: session,
                currentUser: currentUser,
              ),
          ],
        ),
      ),
    );
  }

  void _openSession(TeamSession session) {
    context.go('/sessions/${session.id}');
  }

  Future<void> _editSession(TeamSession session) async {
    final updated = await context.push<TeamSession>(
      '/sessions/${session.id}/edit',
    );
    if (updated != null && mounted) {
      showAppNotification(
        context,
        message: 'Sesión actualizada.',
        type: AppNotificationType.success,
      );
    }
  }

  Future<void> _confirmDelete(TeamSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar sesión'),
        content: const Text(
          'Se eliminarán también las actualizaciones de asistencia de esta '
          'sesión. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(sessionRepositoryProvider).deleteSession(session.id);
      if (mounted) {
        context.pop();
      }
    } on FirebaseException {
      if (mounted) {
        showAppNotification(
          context,
          message: 'No se pudo eliminar la sesión.',
          type: AppNotificationType.error,
        );
      }
    }
  }
}

class SessionTimelineNavigation extends StatelessWidget {
  const SessionTimelineNavigation({
    required this.timeline,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  final SessionTimelinePosition timeline;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.outlined(
          key: const ValueKey('previous-session'),
          tooltip: 'Sesión anterior',
          onPressed: onPrevious,
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: Text(
            '${timeline.position} de ${timeline.total}',
            key: const ValueKey('session-timeline-position'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.blueGrey.shade700,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton.outlined(
          key: const ValueKey('next-session'),
          tooltip: 'Sesión siguiente',
          onPressed: onNext,
          icon: const Icon(Icons.arrow_forward),
        ),
      ],
    );
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({required this.session});

  final TeamSession session;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.sports_basketball_outlined,
              size: 38,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(session.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              formatRelativeDate(session.startTime),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '${formatTime(context, session.startTime)} – '
              '${formatTime(context, session.endTime)}',
              style: TextStyle(color: Colors.blueGrey.shade600),
            ),
            if (session.recurrenceSeriesId != null) ...[
              const SizedBox(height: 12),
              const Chip(
                avatar: Icon(Icons.repeat, size: 18),
                label: Text('Sesión recurrente'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlayerAttendancePanel extends ConsumerStatefulWidget {
  const _PlayerAttendancePanel({
    required this.session,
    required this.currentUser,
  });

  final TeamSession session;
  final TeamRosterMember currentUser;

  @override
  ConsumerState<_PlayerAttendancePanel> createState() =>
      _PlayerAttendancePanelState();
}

class _PlayerAttendancePanelState
    extends ConsumerState<_PlayerAttendancePanel> {
  AttendanceStatus? _savingStatus;
  bool _savingNote = false;

  Future<void> _changeStatus(
    AttendanceRecord current,
    AttendanceStatus status,
  ) async {
    if (_savingStatus != null || current.status.playerEquivalent == status) {
      return;
    }

    setState(() => _savingStatus = status);
    final repository = ref.read(attendanceRepositoryProvider);
    final defaultStatus = resolveAttendanceStatus(
      user: widget.currentUser,
      explicitRecord: null,
      sessionTime: widget.session.startTime,
    );
    try {
      await repository.saveAttendance(
        sessionId: widget.session.id,
        userId: widget.currentUser.id,
        status: status,
        note: current.note ?? '',
        updatedBy: widget.currentUser.id,
        defaultStatus: defaultStatus,
      );
      if (!mounted) {
        return;
      }

      final note = await showOptionalAttendanceNoteDialog(
        context: context,
        status: status,
        initialNote: current.note ?? '',
      );
      if (note != null) {
        await repository.saveAttendance(
          sessionId: widget.session.id,
          userId: widget.currentUser.id,
          status: status,
          note: note,
          updatedBy: widget.currentUser.id,
          defaultStatus: defaultStatus,
        );
      }
      if (mounted) {
        showAppNotification(
          context,
          message: 'Asistencia actualizada: ${status.playerLabel}.',
          type: AppNotificationType.success,
        );
      }
    } on FirebaseException {
      if (mounted) {
        showAppNotification(
          context,
          message: 'No se pudo actualizar tu asistencia.',
          type: AppNotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _savingStatus = null);
      }
    }
  }

  Future<void> _saveNote(AttendanceRecord current, String note) async {
    if (_savingNote) {
      return;
    }
    setState(() => _savingNote = true);
    final defaultStatus = resolveAttendanceStatus(
      user: widget.currentUser,
      explicitRecord: null,
      sessionTime: widget.session.startTime,
    );
    try {
      await ref
          .read(attendanceRepositoryProvider)
          .saveAttendance(
            sessionId: widget.session.id,
            userId: widget.currentUser.id,
            status: current.status,
            note: note,
            updatedBy: widget.currentUser.id,
            defaultStatus: defaultStatus,
          );
      if (mounted) {
        FocusScope.of(context).unfocus();
        showAppNotification(
          context,
          message: 'Nota actualizada.',
          type: AppNotificationType.success,
        );
      }
    } on FirebaseException {
      if (mounted) {
        showAppNotification(
          context,
          message: 'No se pudo guardar la nota.',
          type: AppNotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _savingNote = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(attendanceRepositoryProvider);
    return StreamBuilder<AttendanceRecord?>(
      stream: repository.watchAttendance(
        sessionId: widget.session.id,
        userId: widget.currentUser.id,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final attendance =
            snapshot.data ??
            AttendanceRecord.defaultFor(
              user: widget.currentUser,
              sessionTime: widget.session.startTime,
            );
        final canEdit =
            canPlayerEditAttendance(widget.session) &&
            !attendance.status.isCoachOnly;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Estado', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                if (canEdit) ...[
                  Text(
                    'Selecciona tu estado',
                    style: TextStyle(color: Colors.blueGrey.shade700),
                  ),
                  const SizedBox(height: 10),
                  PlayerAttendanceChoices(
                    selectedStatus: attendance.status,
                    savingStatus: _savingStatus,
                    onSelected: (status) => _changeStatus(attendance, status),
                  ),
                ] else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AttendanceBadge(
                      status: attendance.status,
                      perspective: AttendanceLabelPerspective.player,
                    ),
                  ),
                const SizedBox(height: 24),
                PlayerAttendanceNoteField(
                  note: attendance.note ?? '',
                  enabled: canEdit,
                  saving: _savingNote,
                  onSave: (note) => _saveNote(attendance, note),
                ),
                if (!canEdit) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          attendance.status == AttendanceStatus.notApplicable
                              ? Icons.group_off_outlined
                              : attendance.status.isCoachOnly
                              ? Icons.assignment_late_outlined
                              : Icons.lock_clock_outlined,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            attendance.status == AttendanceStatus.notApplicable
                                ? 'Todavía no pertenecías al equipo cuando se '
                                      'celebró esta sesión.'
                                : attendance.status.isCoachOnly
                                ? 'El entrenador ha registrado esta incidencia.'
                                : 'La sesión ha finalizado. Tu asistencia es '
                                      'de solo lectura.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CoachAttendancePanel extends ConsumerStatefulWidget {
  const _CoachAttendancePanel({
    required this.session,
    required this.currentUser,
  });

  final TeamSession session;
  final TeamRosterMember currentUser;

  @override
  ConsumerState<_CoachAttendancePanel> createState() =>
      _CoachAttendancePanelState();
}

class _CoachAttendancePanelState
    extends ConsumerState<_CoachAttendancePanel> {
  AttendanceStatus? _selectedStatus;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final currentUser = widget.currentUser;
    final teamRepository = ref.watch(teamRepositoryProvider);
    final attendanceRepository = ref.watch(attendanceRepositoryProvider);
    return StreamBuilder<List<TeamRosterMember>>(
      stream: teamRepository.watchTeamMembers(session.teamId),
      builder: (context, membersSnapshot) {
        if (membersSnapshot.hasError) {
          return const Text('No se pudo cargar la plantilla.');
        }
        if (!membersSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final members = membersSnapshot.data!
            .where((member) => member.role == UserRole.player)
            .toList();
        return StreamBuilder<Map<String, AttendanceRecord>>(
          stream: attendanceRepository.watchSessionAttendance(session.id),
          builder: (context, attendanceSnapshot) {
            final savedAttendance =
                attendanceSnapshot.data ?? const <String, AttendanceRecord>{};
            final attendance = {
              for (final member in members)
                member.id:
                    savedAttendance[member.id] ??
                    AttendanceRecord.defaultFor(
                      user: member,
                      sessionTime: session.startTime,
                    ),
            };
            final visibleMembers = _selectedStatus == null
                ? members
                : members
                      .where(
                        (member) =>
                            attendance[member.id]!.status == _selectedStatus,
                      )
                      .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Resumen del equipo',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _AttendanceSummary(
                  attendance: attendance.values,
                  selectedStatus: _selectedStatus,
                  onStatusSelected: (status) =>
                      setState(() => _selectedStatus = status),
                ),
                const SizedBox(height: 22),
                Text(
                  _selectedStatus == null
                      ? 'Plantilla (${members.length})'
                      : 'Plantilla (${visibleMembers.length} '
                            'de ${members.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (members.isEmpty)
                  const EmptyState(
                    icon: Icons.group_off_outlined,
                    title: 'Plantilla vacía',
                    message: 'Comparte el código para añadir jugadores.',
                  )
                else if (visibleMembers.isEmpty)
                  const EmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    title: 'Sin jugadores',
                    message: 'Ningún jugador tiene este estado de asistencia.',
                  )
                else
                  ...visibleMembers.map((member) {
                    final record = attendance[member.id]!;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: CoachAttendanceListItem(
                        member: member,
                        record: record,
                        updateLabel: record.updatedAt == null
                            ? record.status == AttendanceStatus.notApplicable
                                  ? 'Se unió después de esta sesión'
                                  : 'Estado predeterminado'
                            : _formatUpdatedAt(record.updatedAt!),
                        onTap: () async {
                          final draft = await showAttendanceEditor(
                            context: context,
                            initialValue: record,
                            title: member.fullName,
                            showCoachOptions: true,
                          );
                          if (draft != null && context.mounted) {
                            await _saveAttendance(
                              context: context,
                              ref: ref,
                              session: session,
                              targetUser: member,
                              currentUser: currentUser,
                              draft: draft,
                            );
                          }
                        },
                      ),
                    );
                  }),
              ],
            );
          },
        );
      },
    );
  }

  String _formatUpdatedAt(DateTime updatedAt) {
    final local = updatedAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final updatedDay = DateTime(local.year, local.month, local.day);
    final differenceInDays = today.difference(updatedDay).inDays;
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final time = '$hour:$minute';
    if (differenceInDays == 0) {
      return 'Actualizado hoy a las $time';
    }
    if (differenceInDays == 1) {
      return 'Actualizado ayer a las $time';
    }
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return 'Actualizado el $day/$month a las $time';
  }
}

class CoachAttendanceListItem extends StatelessWidget {
  const CoachAttendanceListItem({
    required this.member,
    required this.record,
    required this.updateLabel,
    required this.onTap,
    super.key,
  });

  final TeamRosterMember member;
  final AttendanceRecord record;
  final String updateLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final note = record.note?.trim();
    final hasNote = note != null && note.isNotEmpty;
    return Card(
      child: ListTile(
        minTileHeight: hasNote ? 88 : 72,
        isThreeLine: hasNote,
        leading: CircleAvatar(
          child: Text(
            member.fullName.isEmpty ? '?' : member.fullName[0].toUpperCase(),
          ),
        ),
        title: Text(member.fullName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(updateLabel),
            if (hasNote)
              Text(
                'Nota: $note',
                key: ValueKey('coach-note-preview-${member.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.blueGrey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        trailing: AttendanceBadge(
          status: record.status,
          perspective: AttendanceLabelPerspective.coach,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _AttendanceSummary extends StatelessWidget {
  const _AttendanceSummary({
    required this.attendance,
    required this.selectedStatus,
    required this.onStatusSelected,
  });

  final Iterable<AttendanceRecord> attendance;
  final AttendanceStatus? selectedStatus;
  final ValueChanged<AttendanceStatus?> onStatusSelected;

  @override
  Widget build(BuildContext context) {
    final counts = {for (final status in AttendanceStatus.values) status: 0};
    for (final record in attendance) {
      counts[record.status] = counts[record.status]! + 1;
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: AttendanceStatus.values
          .where((status) => counts[status]! > 0)
          .map(
            (status) => AttendanceStatusChip(
              selected: status == selectedStatus,
              status: status,
              label: '${status.coachLabel}: ${counts[status]}',
              onSelected: (_) => onStatusSelected(
                status == selectedStatus ? null : status,
              ),
            ),
          )
          .toList(),
    );
  }
}

Future<void> _saveAttendance({
  required BuildContext context,
  required WidgetRef ref,
  required TeamSession session,
  required TeamRosterMember targetUser,
  required TeamRosterMember currentUser,
  required AttendanceDraft draft,
}) async {
  try {
    await ref
        .read(attendanceRepositoryProvider)
        .saveAttendance(
          sessionId: session.id,
          userId: targetUser.id,
          status: draft.status,
          note: draft.note,
          updatedBy: currentUser.id,
          defaultStatus: resolveAttendanceStatus(
            user: targetUser,
            explicitRecord: null,
            sessionTime: session.startTime,
          ),
        );
    if (context.mounted) {
      showAppNotification(
        context,
        message: 'Asistencia actualizada.',
        type: AppNotificationType.success,
      );
    }
  } on FirebaseException {
    if (context.mounted) {
      showAppNotification(
        context,
        message: 'No se pudo guardar el estado.',
        type: AppNotificationType.error,
      );
    }
  }
}
