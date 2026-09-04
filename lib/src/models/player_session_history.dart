import 'attendance.dart';
import 'team_membership.dart';
import 'team_session.dart';

/// Mutually exclusive attendance buckets used to filter a player's session
/// history, collapsing the coach-only "unannounced" variants into their
/// player-facing equivalents so counts don't overlap.
enum PlayerAttendanceFilterCategory {
  attending,
  late,
  courtOnly,
  gymOnly,
  absent,
  injured;

  bool matches(AttendanceStatus status) => switch (this) {
    PlayerAttendanceFilterCategory.attending =>
      status == AttendanceStatus.attending,
    PlayerAttendanceFilterCategory.late =>
      status == AttendanceStatus.late ||
          status == AttendanceStatus.lateUnannounced,
    PlayerAttendanceFilterCategory.courtOnly =>
      status == AttendanceStatus.courtOnly,
    PlayerAttendanceFilterCategory.gymOnly =>
      status == AttendanceStatus.gymOnly,
    PlayerAttendanceFilterCategory.absent =>
      status == AttendanceStatus.absent ||
          status == AttendanceStatus.absentUnannounced ||
          status == AttendanceStatus.absentLateNotice,
    PlayerAttendanceFilterCategory.injured =>
      status == AttendanceStatus.injured,
  };

  String get label => switch (this) {
    PlayerAttendanceFilterCategory.attending => 'Asiste',
    PlayerAttendanceFilterCategory.late => 'Llega tarde',
    PlayerAttendanceFilterCategory.courtOnly => 'Solo pista',
    PlayerAttendanceFilterCategory.gymOnly => 'Solo físico',
    PlayerAttendanceFilterCategory.absent => 'No asiste',
    PlayerAttendanceFilterCategory.injured => 'Lesión',
  };

  /// A representative [AttendanceStatus] for this category, used purely to
  /// reuse the existing color/icon defined on [AttendanceStatus].
  AttendanceStatus get representativeStatus => switch (this) {
    PlayerAttendanceFilterCategory.attending => AttendanceStatus.attending,
    PlayerAttendanceFilterCategory.late => AttendanceStatus.late,
    PlayerAttendanceFilterCategory.courtOnly => AttendanceStatus.courtOnly,
    PlayerAttendanceFilterCategory.gymOnly => AttendanceStatus.gymOnly,
    PlayerAttendanceFilterCategory.absent => AttendanceStatus.absent,
    PlayerAttendanceFilterCategory.injured => AttendanceStatus.injured,
  };

  static PlayerAttendanceFilterCategory? fromStatus(AttendanceStatus status) {
    for (final category in values) {
      if (category.matches(status)) {
        return category;
      }
    }
    return null;
  }
}

class PlayerSessionEntry {
  const PlayerSessionEntry({required this.session, required this.status});

  final TeamSession session;
  final AttendanceStatus status;

  PlayerAttendanceFilterCategory? get category =>
      PlayerAttendanceFilterCategory.fromStatus(status);
}

class PlayerSessionHistory {
  const PlayerSessionHistory({required this.entries, required this.counts});

  final List<PlayerSessionEntry> entries;
  final Map<PlayerAttendanceFilterCategory, int> counts;
}

/// Builds the per-session attendance history for [player], most recent
/// session first, excluding sessions before the player joined the team
/// ([AttendanceStatus.notApplicable]).
PlayerSessionHistory buildPlayerSessionHistory({
  required TeamRosterMember player,
  required Iterable<TeamSession> sessions,
  required Map<String, Map<String, AttendanceRecord>> attendanceBySession,
}) {
  final entries = <PlayerSessionEntry>[];
  final counts = {
    for (final category in PlayerAttendanceFilterCategory.values) category: 0,
  };

  for (final session in sessions) {
    final status = resolveAttendanceStatus(
      user: player,
      explicitRecord: attendanceBySession[session.id]?[player.id],
      sessionTime: session.startTime,
    );
    if (status == AttendanceStatus.notApplicable) {
      continue;
    }
    final entry = PlayerSessionEntry(session: session, status: status);
    entries.add(entry);
    final category = entry.category;
    if (category != null) {
      counts[category] = counts[category]! + 1;
    }
  }

  entries.sort(
    (left, right) => right.session.startTime.compareTo(left.session.startTime),
  );

  return PlayerSessionHistory(entries: entries, counts: counts);
}
