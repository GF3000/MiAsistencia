import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../models/attendance.dart';
import '../models/player_motivation.dart';
import '../models/team_session.dart';
import '../providers.dart';
import '../theme/app_theme.dart';

IconData _trendIcon(int change) => change > 0
    ? Icons.trending_up
    : change < 0
    ? Icons.trending_down
    : Icons.trending_flat;

String _signedPoints(int change) => '${change > 0 ? '+' : ''}$change pp';

class _ExpandableKpiCard extends StatefulWidget {
  const _ExpandableKpiCard({
    required this.containerKey,
    required this.toggleKey,
    required this.title,
    required this.subtitle,
    required this.percentage,
    required this.expandedChild,
    required this.loading,
  });

  final ValueKey<String> containerKey;
  final ValueKey<String> toggleKey;
  final String title;
  final String subtitle;
  final int? percentage;
  final Widget expandedChild;
  final bool loading;

  @override
  State<_ExpandableKpiCard> createState() => _ExpandableKpiCardState();
}

class _ExpandableKpiCardState extends State<_ExpandableKpiCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: widget.containerKey,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.navy, AppTheme.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                expanded: _expanded,
                label: _expanded
                    ? 'Contraer indicadores'
                    : 'Expandir indicadores',
                child: InkWell(
                  key: widget.toggleKey,
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              widget.percentage == null
                                  ? '—'
                                  : '${widget.percentage}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const Text(
                              'Asistencia · 30 días',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: const Icon(
                            Icons.expand_more,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: _expanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Divider(color: Colors.white24, height: 1),
                            const SizedBox(height: 14),
                            widget.expandedChild,
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (widget.loading)
                const LinearProgressIndicator(
                  minHeight: 3,
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class TeamPerformancePanel extends ConsumerStatefulWidget {
  const TeamPerformancePanel({
    required this.user,
    required this.teamId,
    required this.teamName,
    required this.completedSessions,
    super.key,
  });

  final AppUser user;
  final String teamId;
  final String teamName;
  final List<TeamSession> completedSessions;

  @override
  ConsumerState<TeamPerformancePanel> createState() =>
      _TeamPerformancePanelState();
}

class _TeamPerformancePanelState extends ConsumerState<TeamPerformancePanel> {
  late Stream<List<AppUser>> _membersStream;
  late Stream<AttendanceHistorySnapshot> _attendanceStream;
  late int _sessionsSignature;

  @override
  void initState() {
    super.initState();
    _configureStreams();
  }

  @override
  void didUpdateWidget(covariant TeamPerformancePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignature = Object.hashAll(
      widget.completedSessions.map((session) => session.id),
    );
    if (oldWidget.teamId != widget.teamId ||
        nextSignature != _sessionsSignature) {
      _configureStreams();
    }
  }

  void _configureStreams() {
    _sessionsSignature = Object.hashAll(
      widget.completedSessions.map((session) => session.id),
    );
    _membersStream = ref
        .read(teamRepositoryProvider)
        .watchMembers(widget.teamId);
    _attendanceStream = ref
        .read(attendanceRepositoryProvider)
        .watchAttendanceForSessions(
          widget.completedSessions.map((session) => session.id),
        );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppUser>>(
      stream: _membersStream,
      builder: (context, membersSnapshot) {
        if (membersSnapshot.hasError) {
          return _fallback(message: 'No se pudieron cargar los datos.');
        }
        if (!membersSnapshot.hasData) {
          return _fallback(loading: true);
        }

        return StreamBuilder<AttendanceHistorySnapshot>(
          stream: _attendanceStream,
          builder: (context, attendanceSnapshot) {
            if (attendanceSnapshot.hasError) {
              return _fallback(message: 'No se pudo cargar el historial.');
            }
            if (!attendanceSnapshot.hasData) {
              return _fallback(loading: true);
            }

            final history = attendanceSnapshot.data!;
            final loadedSessions = widget.completedSessions
                .where(
                  (session) => history.loadedSessionIds.contains(session.id),
                )
                .toList();
            if (widget.user.isCoach) {
              return CoachTeamPerformanceCard(
                teamName: widget.teamName,
                trend: buildTeamAttendanceTrend(
                  members: membersSnapshot.data!,
                  completedSessions: loadedSessions,
                  attendanceBySession: history.attendanceBySession,
                  referenceDate: DateTime.now(),
                ),
                loading: !history.isComplete,
              );
            }
            return PlayerMotivationCard(
              teamName: widget.teamName,
              kpis: buildPlayerMotivationKpis(
                currentPlayer: widget.user,
                members: membersSnapshot.data!,
                completedSessions: loadedSessions,
                attendanceBySession: history.attendanceBySession,
                referenceDate: DateTime.now(),
              ),
              loading: !history.isComplete,
            );
          },
        );
      },
    );
  }

  Widget _fallback({bool loading = false, String? message}) {
    return widget.user.isCoach
        ? CoachTeamPerformanceCard(
            teamName: widget.teamName,
            trend: null,
            loading: loading,
            message: message,
          )
        : PlayerMotivationCard(
            teamName: widget.teamName,
            kpis: null,
            loading: loading,
            message: message,
          );
  }
}

class PlayerMotivationCard extends StatelessWidget {
  const PlayerMotivationCard({
    required this.teamName,
    required this.kpis,
    this.loading = false,
    this.message,
    super.key,
  });

  final String teamName;
  final PlayerMotivationKpis? kpis;
  final bool loading;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final globalRanking = kpis?.globalRanking;
    final recentRanking = kpis?.recentRanking;
    final physicalRanking = kpis?.physicalRanking;
    return _ExpandableKpiCard(
      containerKey: const ValueKey('player-motivation-kpis'),
      toggleKey: const ValueKey('toggle-player-kpis'),
      title: 'Tu rendimiento',
      subtitle: '$teamName · Jugador',
      percentage: kpis?.recentAttendancePercentage,
      loading: loading,
      expandedChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _RankingTile(
                    width: tileWidth,
                    icon: Icons.emoji_events_outlined,
                    rank: globalRanking?.rank,
                    label: 'Global',
                    detail: globalRanking == null
                        ? 'Mínimo 3 sesiones'
                        : '${globalRanking.percentage}% asistencia',
                  ),
                  _RankingTile(
                    width: tileWidth,
                    icon: Icons.calendar_month_outlined,
                    rank: recentRanking?.rank,
                    label: 'Últimos 30 días',
                    detail: recentRanking == null
                        ? 'Sin sesiones'
                        : '${recentRanking.score} asistencias',
                  ),
                  if (kpis?.shouldShowPhysicalRanking == true)
                    _PhysicalRankingTile(ranking: physicalRanking!),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricTile(
                    width: tileWidth,
                    icon: Icons.timer_outlined,
                    value: kpis?.recentPunctualityPercentage == null
                        ? '—'
                        : '${kpis!.recentPunctualityPercentage}%',
                    label: 'Puntualidad',
                    detail: 'Últimos 30 días',
                  ),
                  _MetricTile(
                    width: tileWidth,
                    icon: Icons.local_fire_department_outlined,
                    value: '${kpis?.bestAttendanceStreak ?? 0}',
                    label: 'Mejor racha',
                    detail: 'Sesiones seguidas',
                  ),
                ],
              );
            },
          ),
          if (kpis?.attendancePercentageChange != null) ...[
            const SizedBox(height: 10),
            _MetricTile(
              width: double.infinity,
              icon: _trendIcon(kpis!.attendancePercentageChange!),
              value: _signedPoints(kpis!.attendancePercentageChange!),
              label: 'Evolución',
              detail: 'Antes: ${kpis!.previousAttendancePercentage}%',
            ),
            if (kpis!.attendancePercentageChange! <= -5) ...[
              const SizedBox(height: 10),
              _TrendAlert(
                message:
                    'Tu asistencia ha bajado '
                    '${kpis!.attendancePercentageChange!.abs()} pp.',
              ),
            ],
          ],
          if (kpis?.shouldShowAttendanceStreak == true ||
              kpis?.shouldShowAbsenceStreak == true) ...[
            const SizedBox(height: 10),
            _StreakMetrics(
              attendanceStreak: kpis!.shouldShowAttendanceStreak
                  ? kpis!.attendanceStreak
                  : null,
              absenceStreak: kpis!.shouldShowAbsenceStreak
                  ? kpis!.absenceStreak
                  : null,
            ),
          ],
          const SizedBox(height: 14),
          _ProgressMessage(ranking: globalRanking, fallback: message),
        ],
      ),
    );
  }
}

class _StreakMetrics extends StatelessWidget {
  const _StreakMetrics({
    required this.attendanceStreak,
    required this.absenceStreak,
  });

  final int? attendanceStreak;
  final int? absenceStreak;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Las lesiones no suman ni rompen las rachas.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count =
              (attendanceStreak == null ? 0 : 1) +
              (absenceStreak == null ? 0 : 1);
          final width = count == 1
              ? constraints.maxWidth
              : (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (attendanceStreak != null)
                _StreakTile(
                  width: width,
                  emoji: '🔥',
                  value: attendanceStreak!,
                  label: 'Racha asistiendo',
                ),
              if (absenceStreak != null)
                _StreakTile(
                  width: width,
                  emoji: '👻',
                  value: absenceStreak!,
                  label: 'Racha sin asistir',
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StreakTile extends StatelessWidget {
  const _StreakTile({
    required this.width,
    required this.emoji,
    required this.value,
    required this.label,
  });

  final double width;
  final String emoji;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 23)),
          const SizedBox(width: 9),
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                height: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CoachTeamPerformanceCard extends StatelessWidget {
  const CoachTeamPerformanceCard({
    required this.teamName,
    required this.trend,
    this.loading = false,
    this.message,
    super.key,
  });

  final String teamName;
  final TeamAttendanceTrend? trend;
  final bool loading;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return _ExpandableKpiCard(
      containerKey: const ValueKey('coach-team-performance'),
      toggleKey: const ValueKey('toggle-coach-kpis'),
      title: 'Estado del equipo',
      subtitle: '$teamName · ${trend?.activePlayerCount ?? '—'} jugadores',
      percentage: trend?.recentPercentage,
      loading: loading,
      expandedChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final hasTrend = trend?.percentagePointChange != null;
              final tileWidth = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricTile(
                    width: tileWidth,
                    icon: Icons.event_available_outlined,
                    value: '${trend?.recentSessionCount ?? 0}',
                    label: 'Sesiones',
                    detail: 'Finalizadas',
                  ),
                  _MetricTile(
                    width: tileWidth,
                    icon: Icons.groups_outlined,
                    value: _formatAverage(trend?.averageAvailablePlayerCount),
                    label: 'Media 30 días',
                    detail: 'Jugadores por sesión',
                  ),
                  _MetricTile(
                    width: tileWidth,
                    icon: Icons.stacked_line_chart_outlined,
                    value: _formatAverage(
                      trend?.seasonAverageAvailablePlayerCount,
                    ),
                    label: 'Media temporada',
                    detail: 'Jugadores por sesión',
                  ),
                  _MetricTile(
                    width: tileWidth,
                    icon: Icons.percent_outlined,
                    value: trend?.seasonPercentage == null
                        ? '—'
                        : '${trend!.seasonPercentage}%',
                    label: 'Asistencia temporada',
                    detail: 'Sobre jugadores disponibles',
                  ),
                  _MetricTile(
                    width: tileWidth,
                    icon: Icons.person_off_outlined,
                    value: '${trend?.recentAbsenceCount ?? 0}',
                    label: 'Ausencias',
                    detail: 'Últimos 30 días',
                  ),
                  _MetricTile(
                    width: tileWidth,
                    icon: Icons.schedule_outlined,
                    value: '${trend?.recentLateCount ?? 0}',
                    label: 'Retrasos',
                    detail: 'Últimos 30 días',
                  ),
                  if (hasTrend)
                    _MetricTile(
                      width: tileWidth,
                      icon: _trendIcon(trend!.percentagePointChange!),
                      value: _signedPoints(trend!.percentagePointChange!),
                      label: 'Evolución',
                      detail: 'Antes: ${trend!.previousPercentage}%',
                    ),
                ],
              );
            },
          ),
          if (trend?.percentagePointChange case final change?
              when change <= -5) ...[
            const SizedBox(height: 10),
            _TrendAlert(
              message: 'La asistencia del equipo ha bajado ${change.abs()} pp.',
            ),
          ],
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(message!, style: const TextStyle(color: Colors.white70)),
          ],
        ],
      ),
    );
  }
}

String _formatAverage(double? value) {
  if (value == null) {
    return '—';
  }
  final decimals = value == value.roundToDouble() ? 0 : 1;
  return value.toStringAsFixed(decimals).replaceFirst('.', ',');
}

class _TrendAlert extends StatelessWidget {
  const _TrendAlert({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFC2413B).withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Colors.white,
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.width,
    required this.icon,
    required this.value,
    required this.label,
    required this.detail,
  });

  final double width;
  final IconData icon;
  final String value;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label == 'Asistencia'
          ? 'Las lesiones no se incluyen en el porcentaje.'
          : '',
      child: Container(
        width: width,
        constraints: const BoxConstraints(minHeight: 96),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.accent, size: 19),
                const Spacer(),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingTile extends StatelessWidget {
  const _RankingTile({
    required this.width,
    required this.icon,
    required this.rank,
    required this.label,
    required this.detail,
  });

  final double width;
  final IconData icon;
  final int? rank;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(minHeight: 108),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.accent, size: 21),
              const Spacer(),
              Text(
                rank == null ? '—' : '#$rank',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _PhysicalRankingTile extends StatelessWidget {
  const _PhysicalRankingTile({required this.ranking});

  final PlayerRanking ranking;

  @override
  Widget build(BuildContext context) {
    final positionLabel = ranking.isTopFive ? 'Top 5' : 'Bottom 5';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.fitness_center, color: AppTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ranking físico · $positionLabel',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '#${ranking.rank}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressMessage extends StatelessWidget {
  const _ProgressMessage({required this.ranking, this.fallback});

  final PlayerRanking? ranking;
  final String? fallback;

  @override
  Widget build(BuildContext context) {
    final text = switch (ranking) {
      null => fallback ?? 'Los KPI aparecerán tras la primera sesión.',
      PlayerRanking(rank: 1) => 'Lideras el ranking global.',
      PlayerRanking(
        sessionsToOvertake: final sessions?,
        playerAheadName: final name?,
      ) =>
        'Estás a $sessions ${sessions == 1 ? 'entrenamiento' : 'entrenamientos'} '
            'de superar a $name.',
      _ => 'Sigue sumando sesiones para subir en el ranking.',
    };
    return Row(
      children: [
        const Icon(Icons.trending_up, color: AppTheme.accent, size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
