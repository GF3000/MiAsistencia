import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attendance.dart';
import '../models/team_membership.dart';
import '../models/team_session.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import 'app_notification.dart';
import 'app_widgets.dart';
import 'attendance_editor.dart';

class NextSessionCard extends ConsumerWidget {
  const NextSessionCard({
    required this.session,
    required this.user,
    required this.onOpen,
    super.key,
  });

  final TeamSession session;
  final TeamRosterMember user;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      key: const ValueKey('next-session-card'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('next-session-open-area'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.upcoming_outlined,
                      color: AppTheme.navy,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PRÓXIMA SESIÓN',
                          style: TextStyle(
                            color: Colors.blueGrey.shade600,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          session.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${formatSpanishDate(session.startTime)} · '
                          '${formatTime(context, session.startTime)} – '
                          '${formatTime(context, session.endTime)}',
                          style: TextStyle(color: Colors.blueGrey.shade700),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.arrow_forward),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (user.isCoach)
                _CoachNextSessionSummary(session: session)
              else
                _PlayerQuickAttendance(session: session, user: user),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerQuickAttendance extends ConsumerStatefulWidget {
  const _PlayerQuickAttendance({required this.session, required this.user});

  final TeamSession session;
  final TeamRosterMember user;

  @override
  ConsumerState<_PlayerQuickAttendance> createState() =>
      _PlayerQuickAttendanceState();
}

class _PlayerQuickAttendanceState
    extends ConsumerState<_PlayerQuickAttendance> {
  AttendanceStatus? _savingStatus;

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
      user: widget.user,
      explicitRecord: null,
      sessionTime: widget.session.startTime,
    );
    try {
      await repository.saveAttendance(
        sessionId: widget.session.id,
        userId: widget.user.id,
        status: status,
        note: current.note ?? '',
        updatedBy: widget.user.id,
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
          userId: widget.user.id,
          status: status,
          note: note,
          updatedBy: widget.user.id,
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

  @override
  Widget build(BuildContext context) {
    final stream = ref
        .watch(attendanceRepositoryProvider)
        .watchAttendance(sessionId: widget.session.id, userId: widget.user.id);
    return StreamBuilder<AttendanceRecord?>(
      stream: stream,
      builder: (context, snapshot) {
        final current =
            snapshot.data ??
            AttendanceRecord.defaultFor(
              user: widget.user,
              sessionTime: widget.session.startTime,
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Vas a asistir?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            PlayerAttendanceChoices(
              selectedStatus: current.status,
              savingStatus: _savingStatus,
              onSelected: (status) => _changeStatus(current, status),
            ),
            if (current.note?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                'Nota: ${current.note}',
                style: TextStyle(color: Colors.blueGrey.shade700),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _CoachNextSessionSummary extends ConsumerWidget {
  const _CoachNextSessionSummary({required this.session});

  final TeamSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersStream = ref
        .watch(teamRepositoryProvider)
        .watchTeamMembers(session.teamId);
    final attendanceStream = ref
        .watch(attendanceRepositoryProvider)
        .watchSessionAttendance(session.id);

    return StreamBuilder<List<TeamRosterMember>>(
      stream: membersStream,
      builder: (context, membersSnapshot) {
        return StreamBuilder<Map<String, AttendanceRecord>>(
          stream: attendanceStream,
          builder: (context, attendanceSnapshot) {
            if (!membersSnapshot.hasData || !attendanceSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final summary = buildCoachAttendanceSummary(
              members: membersSnapshot.data!,
              attendance: attendanceSnapshot.data!,
              sessionTime: session.startTime,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = [
                      _SummaryMetric(
                        icon: Icons.sports_basketball_outlined,
                        label: 'En pista',
                        value: '${summary.courtCount}/${summary.totalPlayers}',
                        color: const Color(0xFF2563A5),
                      ),
                      _SummaryMetric(
                        icon: Icons.fitness_center_outlined,
                        label: 'En físico',
                        value:
                            '${summary.physicalCount}/${summary.totalPlayers}',
                        color: const Color(0xFF7650A8),
                      ),
                    ];
                    if (constraints.maxWidth >= 520) {
                      return Row(
                        children: [
                          Expanded(child: cards.first),
                          const SizedBox(width: 12),
                          Expanded(child: cards.last),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        cards.first,
                        const SizedBox(height: 10),
                        cards.last,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB76505).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.schedule_outlined,
                        color: Color(0xFFB76505),
                        size: 20,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          summary.latePlayerNames.isEmpty
                              ? 'Llegan tarde: nadie'
                              : 'Llegan tarde: '
                                    '${summary.latePlayerNames.join(', ')}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
