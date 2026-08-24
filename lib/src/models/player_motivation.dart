import 'app_user.dart';
import 'attendance.dart';
import 'team_membership.dart';
import 'team_session.dart';

class PlayerRanking {
  const PlayerRanking({
    required this.rank,
    required this.totalPlayers,
    required this.score,
    required this.sessionCount,
    required this.playerAheadName,
    required this.sessionsToOvertake,
    this.percentage,
  });

  final int rank;
  final int totalPlayers;
  final int score;
  final int sessionCount;
  final String? playerAheadName;
  final int? sessionsToOvertake;
  final int? percentage;

  bool get isTopFive => rank <= 5;
  bool get isBottomFive => !isTopFive && rank > totalPlayers - 5;
}

class PlayerMotivationKpis {
  const PlayerMotivationKpis({
    required this.globalRanking,
    required this.recentRanking,
    required this.physicalRanking,
    required this.recentAttendancePercentage,
    required this.previousAttendancePercentage,
    required this.recentAttendedSessionCount,
    required this.recentEligibleSessionCount,
    required this.recentPunctualityPercentage,
    required this.attendanceStreak,
    required this.absenceStreak,
    required this.bestAttendanceStreak,
  });

  final PlayerRanking? globalRanking;
  final PlayerRanking? recentRanking;
  final PlayerRanking? physicalRanking;
  final int? recentAttendancePercentage;
  final int? previousAttendancePercentage;
  final int recentAttendedSessionCount;
  final int recentEligibleSessionCount;
  final int? recentPunctualityPercentage;
  final int attendanceStreak;
  final int absenceStreak;
  final int bestAttendanceStreak;

  bool get shouldShowPhysicalRanking =>
      physicalRanking != null &&
      (physicalRanking!.isTopFive || physicalRanking!.isBottomFive);

  bool get shouldShowAttendanceStreak => attendanceStreak >= 6;
  bool get shouldShowAbsenceStreak => absenceStreak >= 2;

  int? get attendancePercentageChange =>
      recentAttendancePercentage == null || previousAttendancePercentage == null
      ? null
      : recentAttendancePercentage! - previousAttendancePercentage!;
}

class TeamAttendanceTrend {
  const TeamAttendanceTrend({
    required this.recentPercentage,
    required this.previousPercentage,
    required this.seasonPercentage,
    required this.activePlayerCount,
    required this.recentSessionCount,
    required this.averageAvailablePlayerCount,
    required this.seasonAverageAvailablePlayerCount,
    required this.recentAbsenceCount,
    required this.recentLateCount,
  });

  final int? recentPercentage;
  final int? previousPercentage;
  final int? seasonPercentage;
  final int activePlayerCount;
  final int recentSessionCount;
  final double? averageAvailablePlayerCount;
  final double? seasonAverageAvailablePlayerCount;
  final int recentAbsenceCount;
  final int recentLateCount;

  int? get percentagePointChange =>
      recentPercentage == null || previousPercentage == null
      ? null
      : recentPercentage! - previousPercentage!;
}

PlayerMotivationKpis buildPlayerMotivationKpis({
  required TeamRosterMember currentPlayer,
  required Iterable<TeamRosterMember> members,
  required Iterable<TeamSession> completedSessions,
  required Map<String, Map<String, AttendanceRecord>> attendanceBySession,
  required DateTime referenceDate,
}) {
  final players = members
      .where((member) => member.active && member.role == UserRole.player)
      .toList();
  if (!players.any((player) => player.id == currentPlayer.id)) {
    players.add(currentPlayer);
  }
  final sessions = completedSessions.toList();
  final recentSessions = _sessionsInWindow(
    sessions,
    from: referenceDate.subtract(const Duration(days: 30)),
    until: referenceDate,
  );
  final previousSessions = _sessionsInWindow(
    sessions,
    from: referenceDate.subtract(const Duration(days: 60)),
    until: referenceDate.subtract(const Duration(days: 30)),
  );

  final globalRanking = _buildRanking(
    currentPlayer: currentPlayer,
    players: players,
    sessions: sessions,
    attendanceBySession: attendanceBySession,
    qualifies: (status) => status.countsForAttendancePercentage,
    rankByPercentage: true,
    minimumEligibleSessions: 3,
  );
  final recentRanking = _buildRanking(
    currentPlayer: currentPlayer,
    players: players,
    sessions: recentSessions,
    attendanceBySession: attendanceBySession,
    qualifies: (status) => status.countsForAttendancePercentage,
  );
  final physicalRanking = _buildRanking(
    currentPlayer: currentPlayer,
    players: players,
    sessions: sessions,
    attendanceBySession: attendanceBySession,
    qualifies: (status) =>
        status == AttendanceStatus.attending ||
        status == AttendanceStatus.gymOnly,
  );

  final recentAttendance = _playerAttendancePercentage(
    player: currentPlayer,
    sessions: recentSessions,
    attendanceBySession: attendanceBySession,
  );
  final previousAttendance = _playerAttendancePercentage(
    player: currentPlayer,
    sessions: previousSessions,
    attendanceBySession: attendanceBySession,
  );
  final recentPunctuality = _playerPunctualityPercentage(
    player: currentPlayer,
    sessions: recentSessions,
    attendanceBySession: attendanceBySession,
  );
  final streaks = _buildCurrentStreaks(
    player: currentPlayer,
    sessions: sessions,
    attendanceBySession: attendanceBySession,
  );

  return PlayerMotivationKpis(
    globalRanking: globalRanking,
    recentRanking: recentRanking,
    physicalRanking: physicalRanking,
    recentAttendancePercentage: recentAttendance.percentage,
    previousAttendancePercentage: previousAttendance.percentage,
    recentAttendedSessionCount: recentAttendance.attended,
    recentEligibleSessionCount: recentAttendance.eligible,
    recentPunctualityPercentage: recentPunctuality,
    attendanceStreak: streaks.attendance,
    absenceStreak: streaks.absence,
    bestAttendanceStreak: streaks.bestAttendance,
  );
}

TeamAttendanceTrend buildTeamAttendanceTrend({
  required Iterable<TeamRosterMember> members,
  required Iterable<TeamSession> completedSessions,
  required Map<String, Map<String, AttendanceRecord>> attendanceBySession,
  required DateTime referenceDate,
}) {
  final players = members
      .where((member) => member.active && member.role == UserRole.player)
      .toList();
  final sessions = completedSessions.toList();
  final recentSessions = _sessionsInWindow(
    sessions,
    from: referenceDate.subtract(const Duration(days: 30)),
    until: referenceDate,
  );
  final previousSessions = _sessionsInWindow(
    sessions,
    from: referenceDate.subtract(const Duration(days: 60)),
    until: referenceDate.subtract(const Duration(days: 30)),
  );

  _TeamPeriodMetrics metricsFor(List<TeamSession> periodSessions) {
    var attended = 0;
    var eligible = 0;
    var absences = 0;
    var late = 0;
    for (final session in periodSessions) {
      for (final player in players) {
        final status = _resolvedStatus(
          player: player,
          session: session,
          attendanceBySession: attendanceBySession,
        );
        if (status == AttendanceStatus.injured ||
            status == AttendanceStatus.notApplicable) {
          continue;
        }
        eligible++;
        if (status.countsForAttendancePercentage) {
          attended++;
        }
        if (_countsAsAbsent(status)) {
          absences++;
        }
        if (_countsAsLate(status)) {
          late++;
        }
      }
    }
    return _TeamPeriodMetrics(
      percentage: eligible == 0 ? null : (attended * 100 / eligible).round(),
      attended: attended,
      absences: absences,
      late: late,
    );
  }

  final recentMetrics = metricsFor(recentSessions);
  final previousMetrics = metricsFor(previousSessions);
  final seasonMetrics = metricsFor(sessions);
  return TeamAttendanceTrend(
    recentPercentage: recentMetrics.percentage,
    previousPercentage: previousMetrics.percentage,
    seasonPercentage: seasonMetrics.percentage,
    activePlayerCount: players.length,
    recentSessionCount: recentSessions.length,
    averageAvailablePlayerCount: recentSessions.isEmpty
        ? null
        : recentMetrics.attended / recentSessions.length,
    seasonAverageAvailablePlayerCount: sessions.isEmpty
        ? null
        : seasonMetrics.attended / sessions.length,
    recentAbsenceCount: recentMetrics.absences,
    recentLateCount: recentMetrics.late,
  );
}

PlayerRanking? _buildRanking({
  required TeamRosterMember currentPlayer,
  required List<TeamRosterMember> players,
  required List<TeamSession> sessions,
  required Map<String, Map<String, AttendanceRecord>> attendanceBySession,
  required bool Function(AttendanceStatus status) qualifies,
  bool rankByPercentage = false,
  int minimumEligibleSessions = 1,
}) {
  if (sessions.isEmpty || players.isEmpty) {
    return null;
  }

  final scores = <String, _RankingScore>{
    for (final player in players)
      player.id: () {
        var score = 0;
        var eligible = 0;
        for (final session in sessions) {
          final status = _resolvedStatus(
            player: player,
            session: session,
            attendanceBySession: attendanceBySession,
          );
          if (status.isAttendancePercentageEligible) {
            eligible++;
          }
          if (qualifies(status)) {
            score++;
          }
        }
        return _RankingScore(score: score, eligible: eligible);
      }(),
  };
  final currentScore = scores[currentPlayer.id];
  if (currentScore == null || currentScore.eligible < minimumEligibleSessions) {
    return null;
  }
  final rankedPlayers = players
      .where((player) => scores[player.id]!.eligible >= minimumEligibleSessions)
      .toList();
  bool isHigher(_RankingScore candidate, _RankingScore reference) =>
      rankByPercentage
      ? candidate.score * reference.eligible >
            reference.score * candidate.eligible
      : candidate.score > reference.score;
  final higherPlayers = rankedPlayers
      .where((player) => isHigher(scores[player.id]!, currentScore))
      .toList();
  final higherScores = higherPlayers.map((player) => scores[player.id]!);
  final rank = higherScores.length + 1;

  String? playerAheadName;
  int? sessionsToOvertake;
  if (higherScores.isNotEmpty) {
    final sortedHigherPlayers = [...higherPlayers]
      ..sort((left, right) {
        final leftScore = scores[left.id]!;
        final rightScore = scores[right.id]!;
        final scoreComparison = rankByPercentage
            ? leftScore.comparePercentageTo(rightScore)
            : leftScore.score.compareTo(rightScore.score);
        return scoreComparison != 0
            ? scoreComparison
            : left.fullName.toLowerCase().compareTo(
                right.fullName.toLowerCase(),
              );
      });
    final playersAhead = sortedHigherPlayers.where((player) {
      final closest = scores[sortedHigherPlayers.first.id]!;
      final candidate = scores[player.id]!;
      return rankByPercentage
          ? candidate.comparePercentageTo(closest) == 0
          : candidate.score == closest.score;
    }).toList();
    playerAheadName = playersAhead.first.fullName;
    final closestHigherScore = scores[playersAhead.first.id]!;
    sessionsToOvertake = rankByPercentage
        ? currentScore.sessionsToOvertake(closestHigherScore)
        : closestHigherScore.score - currentScore.score + 1;
  }

  return PlayerRanking(
    rank: rank,
    totalPlayers: rankedPlayers.length,
    score: currentScore.score,
    sessionCount: currentScore.eligible,
    playerAheadName: playerAheadName,
    sessionsToOvertake: sessionsToOvertake,
    percentage: rankByPercentage
        ? (currentScore.score * 100 / currentScore.eligible).round()
        : null,
  );
}

class _RankingScore {
  const _RankingScore({required this.score, required this.eligible});

  final int score;
  final int eligible;

  int comparePercentageTo(_RankingScore other) =>
      (score * other.eligible).compareTo(other.score * eligible);

  int? sessionsToOvertake(_RankingScore other) {
    final remainingImprovement = other.eligible - other.score;
    if (remainingImprovement == 0) {
      return null;
    }
    final gap = other.score * eligible - score * other.eligible;
    return gap ~/ remainingImprovement + 1;
  }
}

AttendanceStatus _resolvedStatus({
  required TeamRosterMember player,
  required TeamSession session,
  required Map<String, Map<String, AttendanceRecord>> attendanceBySession,
}) {
  return resolveAttendanceStatus(
    user: player,
    explicitRecord: attendanceBySession[session.id]?[player.id],
    sessionTime: session.startTime,
  );
}

List<TeamSession> _sessionsInWindow(
  Iterable<TeamSession> sessions, {
  required DateTime from,
  required DateTime until,
}) {
  return sessions
      .where(
        (session) =>
            !session.startTime.isBefore(from) &&
            session.startTime.isBefore(until),
      )
      .toList();
}

_AttendancePercentage _playerAttendancePercentage({
  required TeamRosterMember player,
  required Iterable<TeamSession> sessions,
  required Map<String, Map<String, AttendanceRecord>> attendanceBySession,
}) {
  var attended = 0;
  var eligible = 0;
  for (final session in sessions) {
    final status = _resolvedStatus(
      player: player,
      session: session,
      attendanceBySession: attendanceBySession,
    );
    if (status == AttendanceStatus.injured ||
        status == AttendanceStatus.notApplicable) {
      continue;
    }
    eligible++;
    if (status.countsForAttendancePercentage) {
      attended++;
    }
  }
  return _AttendancePercentage(attended: attended, eligible: eligible);
}

int? _playerPunctualityPercentage({
  required TeamRosterMember player,
  required Iterable<TeamSession> sessions,
  required Map<String, Map<String, AttendanceRecord>> attendanceBySession,
}) {
  var attended = 0;
  var onTime = 0;
  for (final session in sessions) {
    final status = _resolvedStatus(
      player: player,
      session: session,
      attendanceBySession: attendanceBySession,
    );
    if (!status.countsForAttendancePercentage) {
      continue;
    }
    attended++;
    if (!_countsAsLate(status)) {
      onTime++;
    }
  }
  return attended == 0 ? null : (onTime * 100 / attended).round();
}

class _AttendancePercentage {
  const _AttendancePercentage({required this.attended, required this.eligible});

  final int attended;
  final int eligible;

  int? get percentage =>
      eligible == 0 ? null : (attended * 100 / eligible).round();
}

_AttendanceStreaks _buildCurrentStreaks({
  required TeamRosterMember player,
  required Iterable<TeamSession> sessions,
  required Map<String, Map<String, AttendanceRecord>> attendanceBySession,
}) {
  final orderedSessions = sessions.toList()
    ..sort((left, right) => right.startTime.compareTo(left.startTime));
  var attendance = 0;
  var absence = 0;
  var runningAttendance = 0;
  var bestAttendance = 0;

  for (final session in orderedSessions) {
    final status = _resolvedStatus(
      player: player,
      session: session,
      attendanceBySession: attendanceBySession,
    );
    if (status == AttendanceStatus.injured ||
        status == AttendanceStatus.notApplicable) {
      continue;
    }
    if (status.countsForAttendancePercentage) {
      runningAttendance++;
      if (runningAttendance > bestAttendance) {
        bestAttendance = runningAttendance;
      }
    } else {
      runningAttendance = 0;
    }
  }

  for (final session in orderedSessions) {
    final status = _resolvedStatus(
      player: player,
      session: session,
      attendanceBySession: attendanceBySession,
    );
    if (status == AttendanceStatus.injured ||
        status == AttendanceStatus.notApplicable) {
      continue;
    }
    if (status.countsForAttendancePercentage) {
      if (absence > 0) {
        break;
      }
      attendance++;
    } else {
      if (attendance > 0) {
        break;
      }
      absence++;
    }
  }
  return _AttendanceStreaks(
    attendance: attendance,
    absence: absence,
    bestAttendance: bestAttendance,
  );
}

class _AttendanceStreaks {
  const _AttendanceStreaks({
    required this.attendance,
    required this.absence,
    required this.bestAttendance,
  });

  final int attendance;
  final int absence;
  final int bestAttendance;
}

class _TeamPeriodMetrics {
  const _TeamPeriodMetrics({
    required this.percentage,
    required this.attended,
    required this.absences,
    required this.late,
  });

  final int? percentage;
  final int attended;
  final int absences;
  final int late;
}

bool _countsAsLate(AttendanceStatus status) =>
    status == AttendanceStatus.late ||
    status == AttendanceStatus.lateUnannounced;

bool _countsAsAbsent(AttendanceStatus status) =>
    status == AttendanceStatus.absent ||
    status == AttendanceStatus.absentUnannounced ||
    status == AttendanceStatus.absentLateNotice;
