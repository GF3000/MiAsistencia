import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/app_user.dart';
import '../models/attendance.dart';
import '../models/player_motivation.dart';
import '../models/player_session_history.dart';
import '../models/team_membership.dart';
import '../models/team_session.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';
import '../widgets/async_state_view.dart';
import '../widgets/attendance_editor.dart';
import '../widgets/player_motivation_kpis.dart';

class PlayerDetailScreen extends ConsumerStatefulWidget {
  const PlayerDetailScreen({required this.memberId, super.key});

  final String memberId;

  @override
  ConsumerState<PlayerDetailScreen> createState() =>
      _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends ConsumerState<PlayerDetailScreen> {
  Stream<AttendanceHistorySnapshot>? _attendanceStream;
  int? _sessionsSignature;
  PlayerAttendanceFilterCategory? _selectedCategory;

  void _configureAttendanceStream(List<TeamSession> completedSessions) {
    final signature = Object.hashAll(
      completedSessions.map((session) => session.id),
    );
    if (_sessionsSignature == signature) {
      return;
    }
    _sessionsSignature = signature;
    _attendanceStream = ref
        .read(attendanceRepositoryProvider)
        .watchAttendanceForSessions(
          completedSessions.map((session) => session.id),
        );
  }

  void _goToPlayer(TeamRosterMember target) {
    setState(() => _selectedCategory = null);
    context.pushReplacement('/team/players/${target.id}');
  }

  @override
  Widget build(BuildContext context) {
    final membership = ref.watch(currentMembershipProvider);
    if (membership == null) {
      return const AppLoadingView();
    }
    if (!membership.isCoach) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No tienes acceso a esta pantalla.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Volver al inicio'),
              ),
            ],
          ),
        ),
      );
    }

    final teamId = membership.teamId;
    final membersState = ref.watch(teamMembersProvider(teamId));
    final sessionsState = ref.watch(teamSessionsProvider(teamId));
    final teamName = ref.watch(teamProvider(teamId)).value?.name ?? '';

    return membersState.when(
      loading: () => const AppLoadingView(),
      error: (error, stackTrace) => AppErrorView(
        message: 'No se pudo cargar la plantilla.',
        onRetry: () => ref.invalidate(teamMembersProvider(teamId)),
      ),
      data: (members) {
        final players = members
            .where((member) => member.role == UserRole.player && member.active)
            .toList()
          ..sort(
            (left, right) =>
                left.fullName.toLowerCase().compareTo(right.fullName.toLowerCase()),
          );
        final index = players.indexWhere((player) => player.id == widget.memberId);
        if (index < 0) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('El jugador ya no está en el equipo.')),
          );
        }
        final player = players[index];
        final previous = index > 0 ? players[index - 1] : null;
        final next = index < players.length - 1 ? players[index + 1] : null;

        return sessionsState.when(
          loading: () => const AppLoadingView(),
          error: (error, stackTrace) => AppErrorView(
            message: 'No se pudieron cargar las sesiones.',
            onRetry: () => ref.invalidate(teamSessionsProvider(teamId)),
          ),
          data: (sessions) {
            final now = DateTime.now();
            final completedSessions = sessions
                .where((session) => session.endTime.isBefore(now))
                .toList();
            _configureAttendanceStream(completedSessions);

            return StreamBuilder<AttendanceHistorySnapshot>(
              stream: _attendanceStream,
              builder: (context, snapshot) {
                final history = snapshot.data;
                final loadedSessions = history == null
                    ? const <TeamSession>[]
                    : completedSessions
                        .where(
                          (session) =>
                              history.loadedSessionIds.contains(session.id),
                        )
                        .toList();
                final attendanceBySession = history?.attendanceBySession ?? const {};

                final stats = buildPlayerAttendanceStats(
                  player: player,
                  sessions: loadedSessions,
                  attendanceBySession: attendanceBySession,
                );
                final kpis = buildPlayerMotivationKpis(
                  currentPlayer: player,
                  members: players,
                  completedSessions: loadedSessions,
                  attendanceBySession: attendanceBySession,
                  referenceDate: now,
                );
                final sessionHistory = buildPlayerSessionHistory(
                  player: player,
                  sessions: loadedSessions,
                  attendanceBySession: attendanceBySession,
                );
                final visibleEntries = _selectedCategory == null
                    ? sessionHistory.entries
                    : sessionHistory.entries
                        .where((entry) => entry.category == _selectedCategory)
                        .toList();
                final loading = history == null || !history.isComplete;

                return Scaffold(
                  appBar: AppBar(title: Text(player.fullName)),
                  body: AppPageBody(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PlayerTimelineNavigation(
                          position: index + 1,
                          total: players.length,
                          onPrevious:
                              previous == null ? null : () => _goToPlayer(previous),
                          onNext: next == null ? null : () => _goToPlayer(next),
                        ),
                        const SizedBox(height: 12),
                        _PlayerSummaryHeader(stats: stats),
                        const SizedBox(height: 16),
                        PlayerMotivationCard(
                          teamName: teamName,
                          kpis: kpis,
                          loading: loading,
                          title: 'Rendimiento',
                          subtitleLabel: player.fullName,
                          expanded: ref.watch(
                            playerPerformanceCardExpandedProvider,
                          ),
                          onExpandedChanged: (value) => ref
                              .read(
                                playerPerformanceCardExpandedProvider.notifier,
                              )
                              .set(value),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Filtrar por estado',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        _FilterChipsRow(
                          counts: sessionHistory.counts,
                          selected: _selectedCategory,
                          onSelected: (category) => setState(() {
                            _selectedCategory =
                                _selectedCategory == category ? null : category;
                          }),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Sesiones (${visibleEntries.length})',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        if (loadedSessions.isEmpty)
                          const EmptyState(
                            icon: Icons.query_stats_outlined,
                            title: 'Todavía no hay estadísticas',
                            message:
                                'Los datos aparecerán cuando termine la primera '
                                'sesión.',
                          )
                        else if (visibleEntries.isEmpty)
                          const EmptyState(
                            icon: Icons.filter_alt_off_outlined,
                            title: 'Sin sesiones',
                            message: 'Ninguna sesión coincide con este filtro.',
                          )
                        else
                          ...visibleEntries.map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _SessionHistoryTile(
                                entry: entry,
                                onTap: () =>
                                    context.push('/sessions/${entry.session.id}'),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _PlayerTimelineNavigation extends StatelessWidget {
  const _PlayerTimelineNavigation({
    required this.position,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final int position;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.outlined(
          key: const ValueKey('previous-player'),
          tooltip: 'Jugador anterior',
          onPressed: onPrevious,
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: Text(
            '$position de $total',
            key: const ValueKey('player-timeline-position'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.blueGrey.shade700,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton.outlined(
          key: const ValueKey('next-player'),
          tooltip: 'Jugador siguiente',
          onPressed: onNext,
          icon: const Icon(Icons.arrow_forward),
        ),
      ],
    );
  }
}

class _PlayerSummaryHeader extends StatelessWidget {
  const _PlayerSummaryHeader({required this.stats});

  final PlayerAttendanceStats stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            _SummaryStat(
              value: stats.attendancePercentage == null
                  ? '—'
                  : '${stats.attendancePercentage}%',
              label: 'Asistencia',
            ),
            _SummaryStat(value: '${stats.sessionCount}', label: 'Sesiones'),
            _SummaryStat(
              value: '${stats.lateCount}',
              label: 'Retrasos',
              color: const Color(0xFFB76505),
            ),
            _SummaryStat(
              value: '${stats.absenceCount}',
              label: 'Faltas',
              color: const Color(0xFF5C6670),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color ?? AppTheme.primary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow({
    required this.counts,
    required this.selected,
    required this.onSelected,
  });

  final Map<PlayerAttendanceFilterCategory, int> counts;
  final PlayerAttendanceFilterCategory? selected;
  final ValueChanged<PlayerAttendanceFilterCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final visibleCategories = PlayerAttendanceFilterCategory.values
        .where((category) => counts[category]! > 0)
        .toList();
    if (visibleCategories.isEmpty) {
      return Text(
        'Sin sesiones registradas todavía.',
        style: TextStyle(color: Colors.blueGrey.shade600),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: visibleCategories.map((category) {
        return AttendanceStatusChip(
          key: ValueKey('player-filter-chip-${category.name}'),
          status: category.representativeStatus,
          label: '${category.label}: ${counts[category]}',
          selected: category == selected,
          onSelected: (_) => onSelected(category),
        );
      }).toList(),
    );
  }
}

class _SessionHistoryTile extends StatelessWidget {
  const _SessionHistoryTile({required this.entry, required this.onTap});

  final PlayerSessionEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final session = entry.session;
    return Card(
      child: ListTile(
        key: ValueKey('player-session-${session.id}'),
        title: Text(session.title),
        subtitle: Text(
          '${formatSpanishDate(session.startTime)} · '
          '${formatTime(context, session.startTime)}',
        ),
        trailing: AttendanceBadge(
          status: entry.status,
          perspective: AttendanceLabelPerspective.coach,
        ),
        onTap: onTap,
      ),
    );
  }
}
