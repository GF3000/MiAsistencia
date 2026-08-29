import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/app_user.dart';
import '../models/attendance.dart';
import '../models/team_membership.dart';
import '../models/team_session.dart';
import '../providers.dart';
import '../repositories/team_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_notification.dart';
import '../widgets/app_widgets.dart';
import '../widgets/async_state_view.dart';
import '../widgets/next_session_card.dart';
import '../widgets/player_motivation_kpis.dart';
import '../widgets/player_attendance_table.dart';
import '../widgets/session_view_switcher.dart';
import '../widgets/team_calendar.dart';
import '../widgets/team_selector.dart';
import 'batch_attendance_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  SessionViewMode _selectedView = SessionViewMode.list;
  final Set<String> _selectedSessionIds = {};

  TeamRosterMember get _user => ref.read(currentMembershipProvider)!;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentMembershipProvider);
    if (user == null) {
      return const AppLoadingView();
    }
    final teamId = user.teamId;
    final teamState = ref.watch(teamProvider(teamId));
    final sessionsState = ref.watch(teamSessionsProvider(teamId));

    return Scaffold(
      appBar: AppBar(
        title: TeamDropdown(
          membership: user,
          teamName: teamState.value?.name ?? 'Mi Asistencia',
        ),
        actions: [
          if (user.isCoach)
            IconButton(
              tooltip: 'Administrar equipo',
              onPressed: () => context.push('/team/manage'),
              icon: const Icon(Icons.manage_accounts_outlined),
            ),
          PopupMenuButton<String>(
            tooltip: 'Cuenta',
            constraints: const BoxConstraints(minWidth: 310, maxWidth: 350),
            onSelected: (value) {
              switch (value) {
                case 'leave-team':
                  _leaveTeam();
                case 'logout':
                  _signOut();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                height: 64,
                child: _AccountMenuHeader(user: user),
              ),
              const PopupMenuDivider(),
              if (user.canLeaveTeam) ...[
                const PopupMenuItem(
                  value: 'leave-team',
                  height: 76,
                  child: _AccountMenuAction(
                    icon: Icons.group_remove_outlined,
                    color: Color(0xFFB45309),
                    title: 'Salir de este equipo',
                    description: 'Mantienes tus otros equipos',
                  ),
                ),
                const PopupMenuDivider(),
              ],
              PopupMenuItem(
                value: 'logout',
                height: 76,
                child: _AccountMenuAction(
                  icon: Icons.logout,
                  color: Theme.of(context).colorScheme.error,
                  title: 'Cerrar sesión',
                  description: 'Salir de esta cuenta',
                ),
              ),
            ],
          ),
        ],
      ),
      body: sessionsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => AppErrorView(
          message: 'No se pudo cargar el calendario.',
          onRetry: () => ref.invalidate(teamSessionsProvider(teamId)),
        ),
        data: (allSessions) {
          final now = DateTime.now();
          final upcoming = allSessions
              .where((session) => canPlayerEditAttendance(session, at: now))
              .toList();
          final completed = allSessions
              .where((session) => !canPlayerEditAttendance(session, at: now))
              .toList();
          final selectedSessions = allSessions
              .where((session) => _selectedSessionIds.contains(session.id))
              .toList();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(teamSessionsProvider(teamId));
              await ref.read(teamSessionsProvider(teamId).future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TeamPerformancePanel(
                          user: user,
                          teamId: teamId,
                          teamName: teamState.when(
                            loading: () => 'Tu equipo',
                            error: (error, stackTrace) => 'Tu equipo',
                            data: (team) => team?.name ?? 'Tu equipo',
                          ),
                          completedSessions: completed,
                        ),
                        const SizedBox(height: 24),
                        if (selectedSessions.isEmpty &&
                            upcoming.isNotEmpty) ...[
                          NextSessionCard(
                            session: upcoming.first,
                            user: user,
                            onOpen: () => context.push(
                              '/sessions/${upcoming.first.id}',
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        SessionViewSwitcher(
                          value: _selectedView,
                          showPlayers: user.isCoach,
                          onChanged: (value) =>
                              setState(() => _selectedView = value),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Text(switch (_selectedView) {
                                SessionViewMode.list => 'Próximas sesiones',
                                SessionViewMode.calendar =>
                                  'Calendario del equipo',
                                SessionViewMode.players =>
                                  'Estadísticas de jugadores',
                              }, style: Theme.of(context).textTheme.titleLarge),
                            ),
                            if (!user.isCoach && upcoming.isNotEmpty)
                              TextButton.icon(
                                onPressed: () => context.push(
                                  '/sessions/batch-attendance',
                                  extra: upcoming,
                                ),
                                icon: const Icon(Icons.library_add_check),
                                label: const Text('Seleccionar varias'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_selectedView == SessionViewMode.players)
                          PlayerAttendanceOverview(
                            teamId: teamId,
                            completedSessions: completed,
                          )
                        else if (_selectedView == SessionViewMode.calendar)
                          TeamCalendarView(
                            sessions: allSessions,
                            onSessionSelected: _handleSessionTap,
                            onEmptyDateSelected: user.isCoach
                                ? (date) =>
                                      _openCreateSession(initialDate: date)
                                : null,
                          )
                        else if (upcoming.isEmpty)
                          EmptyState(
                            icon: Icons.event_available_outlined,
                            title: 'No hay sesiones próximas',
                            message: user.isCoach
                                ? 'Crea la primera sesión del equipo con el '
                                      'botón inferior.'
                                : 'Tu entrenador todavía no ha creado nuevas '
                                      'sesiones.',
                          )
                        else
                          ...upcoming.map(
                            (session) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _SessionCard(
                                session: session,
                                user: user,
                                selected: _selectedSessionIds.contains(
                                  session.id,
                                ),
                                selectionMode: _selectedSessionIds.isNotEmpty,
                                onLongPress: () =>
                                    _toggleSessionSelection(session),
                                onEdit:
                                    user.isCoach && _selectedSessionIds.isEmpty
                                    ? () => _editSession(session)
                                    : null,
                                onTap: () => _handleSessionTap(session),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: user.isCoach && _selectedSessionIds.isEmpty
          ? FloatingActionButton.extended(
              onPressed: _openCreateSession,
              icon: const Icon(Icons.add),
              label: const Text('Nueva sesión'),
            )
          : null,
      bottomNavigationBar: _selectedSessionIds.isEmpty
          ? null
          : sessionsState.when<Widget?>(
              loading: () => null,
              error: (error, stackTrace) => null,
              data: (allSessions) {
                final selectedSessions = allSessions
                    .where(
                      (session) => _selectedSessionIds.contains(session.id),
                    )
                    .toList();
                if (selectedSessions.isEmpty) {
                  return null;
                }
                return SessionSelectionBottomBar(
                  count: selectedSessions.length,
                  isCoach: user.isCoach,
                  onClear: _clearSessionSelection,
                  onEdit: () => _batchEditSessions(selectedSessions),
                  onDelete: () => _deleteSelectedSessions(selectedSessions),
                  onAttendance: () => _batchAttendance(selectedSessions),
                );
              },
            ),
    );
  }

  void _handleSessionTap(TeamSession session) {
    if (_selectedSessionIds.isNotEmpty) {
      _toggleSessionSelection(session);
      return;
    }
    context.push('/sessions/${session.id}');
  }

  void _openCreateSession({DateTime? initialDate}) {
    context.push('/sessions/new', extra: initialDate);
  }

  void _toggleSessionSelection(TeamSession session) {
    if (!_user.isCoach && !canPlayerEditAttendance(session)) {
      showAppNotification(
        context,
        message: 'No puedes modificar la asistencia de una sesión finalizada.',
        type: AppNotificationType.warning,
      );
      return;
    }
    setState(() {
      if (!_selectedSessionIds.add(session.id)) {
        _selectedSessionIds.remove(session.id);
      }
    });
  }

  void _clearSessionSelection() {
    setState(_selectedSessionIds.clear);
  }

  Future<void> _batchAttendance(List<TeamSession> sessions) async {
    final saved = await showBatchAttendanceEditor(
      context: context,
      user: _user,
      sessions: sessions,
    );
    if (saved == true && mounted) {
      _clearSessionSelection();
    }
  }

  Future<void> _batchEditSessions(List<TeamSession> sessions) async {
    final saved = await context.push<bool>(
      '/sessions/batch-edit',
      extra: sessions,
    );
    if (saved == true && mounted) {
      _clearSessionSelection();
      showAppNotification(
        context,
        message: '${sessions.length} sesiones modificadas.',
        type: AppNotificationType.success,
      );
    }
  }

  Future<void> _deleteSelectedSessions(List<TeamSession> sessions) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.delete_forever_outlined,
          color: Theme.of(context).colorScheme.error,
        ),
        title: Text('Eliminar ${sessions.length} sesiones'),
        content: const Text(
          'También se eliminarán sus registros de asistencia. '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(sessionRepositoryProvider).deleteSessions(sessions);
      if (mounted) {
        _clearSessionSelection();
        showAppNotification(
          context,
          message: '${sessions.length} sesiones eliminadas.',
          type: AppNotificationType.success,
        );
      }
    } on FirebaseException {
      if (mounted) {
        showAppNotification(
          context,
          message: 'No se pudieron eliminar todas las sesiones.',
          type: AppNotificationType.error,
        );
      }
    }
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

  Future<void> _leaveTeam() async {
    final user = _user;
    if (!user.canLeaveTeam) {
      return;
    }
    final confirmed = await _confirmAccountAction(
      icon: Icons.group_remove_outlined,
      color: const Color(0xFFB45309),
      title: 'Salir de este equipo',
      message:
          'Dejarás de ver el calendario y las sesiones de este equipo. '
          'Mantendrás el acceso a tus otros equipos.',
      confirmLabel: 'Salir de este equipo',
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await ref
          .read(teamRepositoryProvider)
          .leaveTeam(teamId: user.teamId!, userId: user.id);
    } on TeamException catch (error) {
      if (mounted) {
        showAppNotification(
          context,
          message: error.message,
          type: AppNotificationType.error,
        );
      }
    } on FirebaseException {
      if (mounted) {
        showAppNotification(
          context,
          message: 'No se pudo abandonar el equipo. Inténtalo de nuevo.',
          type: AppNotificationType.error,
        );
      }
    }
  }

  Future<void> _signOut() async {
    final confirmed = await _confirmAccountAction(
      icon: Icons.logout,
      color: Theme.of(context).colorScheme.error,
      title: 'Cerrar sesión',
      message:
          'Cerrarás la sesión en este dispositivo. Tu cuenta, equipo y datos '
          'no se modificarán.',
      confirmLabel: 'Cerrar sesión',
      destructive: true,
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(authRepositoryProvider).signOut();
    } on FirebaseException {
      if (mounted) {
        showAppNotification(
          context,
          message: 'No se pudo cerrar la sesión. Inténtalo de nuevo.',
          type: AppNotificationType.error,
        );
      }
    }
  }

  Future<bool?> _confirmAccountAction({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          key: const ValueKey('account-confirmation-dialog'),
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        style: destructive
                            ? FilledButton.styleFrom(backgroundColor: color)
                            : null,
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: Text(confirmLabel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SessionSelectionBottomBar extends StatelessWidget {
  const SessionSelectionBottomBar({
    required this.count,
    required this.isCoach,
    required this.onClear,
    required this.onEdit,
    required this.onDelete,
    required this.onAttendance,
    Key? widgetKey,
  }) : super(key: widgetKey);

  final int count;
  final bool isCoach;
  final VoidCallback onClear;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAttendance;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('session-selection-bottom-bar'),
      color: Colors.white,
      elevation: 18,
      shadowColor: AppTheme.navy.withValues(alpha: 0.25),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final header = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const ValueKey('clear-session-selection'),
                      tooltip: 'Cancelar selección',
                      onPressed: onClear,
                      icon: const Icon(Icons.close),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '$count ${count == 1 ? 'sesión seleccionada' : 'sesiones seleccionadas'}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                );
                final actions = _buildActions(context);
                if (constraints.maxWidth >= 650) {
                  return Row(
                    children: [
                      Expanded(child: header),
                      ...actions
                          .map(
                            (action) => SizedBox(
                              width: isCoach ? 150 : 220,
                              child: action,
                            ),
                          )
                          .toList()
                          .separatedBy(const SizedBox(width: 8)),
                    ],
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 8),
                    Row(
                      children: actions
                          .map((action) => Expanded(child: action))
                          .toList()
                          .separatedBy(const SizedBox(width: 8)),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    if (!isCoach) {
      return [
        FilledButton.icon(
          key: const ValueKey('batch-attendance-action'),
          onPressed: onAttendance,
          icon: const Icon(Icons.done_all),
          label: const Text('Cambiar asistencia'),
        ),
      ];
    }
    return [
      FilledButton.icon(
        key: const ValueKey('batch-edit-action'),
        onPressed: onEdit,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Modificar'),
      ),
      OutlinedButton.icon(
        key: const ValueKey('batch-delete-action'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          side: BorderSide(color: Theme.of(context).colorScheme.error),
        ),
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline),
        label: const Text('Eliminar'),
      ),
    ];
  }
}

extension _SeparatedWidgets on List<Widget> {
  List<Widget> separatedBy(Widget separator) {
    if (length < 2) {
      return this;
    }
    return [
      for (var index = 0; index < length; index++) ...[
        if (index > 0) separator,
        this[index],
      ],
    ];
  }
}

class _AccountMenuHeader extends StatelessWidget {
  const _AccountMenuHeader({required this.user});

  final TeamRosterMember user;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
          child: const Icon(
            Icons.person_outline,
            color: AppTheme.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                user.role.label,
                style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountMenuAction extends StatelessWidget {
  const _AccountMenuAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SessionCard extends ConsumerWidget {
  const _SessionCard({
    required this.session,
    required this.user,
    required this.onTap,
    this.onEdit,
    this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
  });

  final TeamSession session;
  final TeamRosterMember user;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceStream = user.isCoach
        ? null
        : ref
              .watch(attendanceRepositoryProvider)
              .watchAttendance(sessionId: session.id, userId: user.id);
    return Card(
      key: ValueKey('session-card-${session.id}'),
      color: selected ? AppTheme.primary.withValues(alpha: 0.08) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? AppTheme.primary : const Color(0xFFE4EAF0),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.sports_basketball_outlined,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          formatRelativeDate(session.startTime),
                          style: TextStyle(color: Colors.blueGrey.shade700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${formatTime(context, session.startTime)} – '
                          '${formatTime(context, session.endTime)}',
                          style: TextStyle(color: Colors.blueGrey.shade600),
                        ),
                      ],
                    ),
                  ),
                  if (selectionMode)
                    Checkbox(value: selected, onChanged: (_) => onTap())
                  else if (onEdit != null)
                    PopupMenuButton<String>(
                      key: ValueKey('session-menu-${session.id}'),
                      tooltip: 'Opciones de la sesión',
                      onSelected: (value) {
                        if (value == 'edit') {
                          onEdit!();
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Editar sesión'),
                          ),
                        ),
                      ],
                    )
                  else
                    const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (attendanceStream != null)
                    StreamBuilder<AttendanceRecord?>(
                      stream: attendanceStream,
                      builder: (context, snapshot) => AttendanceBadge(
                        status:
                            snapshot.data?.status ??
                            resolveAttendanceStatus(
                              user: user,
                              explicitRecord: null,
                              sessionTime: session.startTime,
                            ),
                        perspective: AttendanceLabelPerspective.player,
                      ),
                    ),
                  if (user.isCoach) ...[
                    const Spacer(),
                    _AttendingPlayerCount(session: session),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttendingPlayerCount extends ConsumerWidget {
  const _AttendingPlayerCount({required this.session});

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
        final players = membersSnapshot.data
            ?.where((member) => member.role == UserRole.player)
            .toList();
        if (players == null) {
          return const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        return StreamBuilder<Map<String, AttendanceRecord>>(
          stream: attendanceStream,
          builder: (context, attendanceSnapshot) {
            if (!attendanceSnapshot.hasData) {
              return const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            final attending = countAttendingPlayers(
              members: players,
              attendance: attendanceSnapshot.data!,
              sessionTime: session.startTime,
            );
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.groups_2_outlined,
                  size: 18,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 5),
                Text(
                  '$attending/${players.length} asisten',
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
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
