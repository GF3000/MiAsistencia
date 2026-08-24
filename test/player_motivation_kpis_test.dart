import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/models/attendance.dart';
import 'package:mi_asistencia/src/models/player_motivation.dart';
import 'package:mi_asistencia/src/models/team_session.dart';
import 'package:mi_asistencia/src/theme/app_theme.dart';
import 'package:mi_asistencia/src/widgets/player_motivation_kpis.dart';

void main() {
  test(
    'calculates rankings and excludes injuries from attendance percentage',
    () {
      const current = AppUser(
        id: 'diego',
        email: 'diego@example.com',
        fullName: 'Diego',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      );
      const ana = AppUser(
        id: 'ana',
        email: 'ana@example.com',
        fullName: 'Ana',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      );
      const bea = AppUser(
        id: 'bea',
        email: 'bea@example.com',
        fullName: 'Bea',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      );
      const carla = AppUser(
        id: 'carla',
        email: 'carla@example.com',
        fullName: 'Carla',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      );
      final sessions = List.generate(6, (index) {
        final month = index < 3 ? 7 : 8;
        return TeamSession(
          id: 'session-$index',
          teamId: 'team-1',
          title: 'Sesión $index',
          startTime: DateTime(2026, month, index + 1, 19),
          endTime: DateTime(2026, month, index + 1, 20),
        );
      });
      final diegoStatuses = [
        AttendanceStatus.attending,
        AttendanceStatus.late,
        AttendanceStatus.courtOnly,
        AttendanceStatus.gymOnly,
        AttendanceStatus.absentUnannounced,
        AttendanceStatus.injured,
      ];
      final attendance = {
        for (var index = 0; index < sessions.length; index++)
          sessions[index].id: {
            current.id: AttendanceRecord(
              userId: current.id,
              status: diegoStatuses[index],
            ),
            ana.id: AttendanceRecord(
              userId: ana.id,
              status: AttendanceStatus.attending,
            ),
            bea.id: AttendanceRecord(
              userId: bea.id,
              status: index == 5
                  ? AttendanceStatus.absent
                  : AttendanceStatus.attending,
            ),
            carla.id: AttendanceRecord(
              userId: carla.id,
              status: index < 4
                  ? AttendanceStatus.attending
                  : index == 4
                  ? AttendanceStatus.absent
                  : AttendanceStatus.injured,
            ),
          },
      };

      final kpis = buildPlayerMotivationKpis(
        currentPlayer: current,
        members: const [current, ana, bea, carla],
        completedSessions: sessions,
        attendanceBySession: attendance,
        referenceDate: DateTime(2026, 8, 24),
      );

      expect(kpis.globalRanking?.rank, 3);
      expect(kpis.globalRanking?.score, 4);
      expect(kpis.globalRanking?.percentage, 80);
      expect(kpis.globalRanking?.playerAheadName, 'Bea');
      expect(kpis.globalRanking?.sessionsToOvertake, 2);
      expect(kpis.recentRanking?.rank, 3);
      expect(kpis.recentRanking?.score, 1);
      expect(kpis.physicalRanking?.rank, 4);
      expect(kpis.shouldShowPhysicalRanking, isTrue);
      expect(kpis.recentAttendedSessionCount, 1);
      expect(kpis.recentEligibleSessionCount, 2);
      expect(kpis.recentAttendancePercentage, 50);
      expect(kpis.previousAttendancePercentage, 100);
      expect(kpis.attendancePercentageChange, -50);
      expect(kpis.recentPunctualityPercentage, 100);
      expect(kpis.attendanceStreak, 0);
      expect(kpis.absenceStreak, 1);
      expect(kpis.bestAttendanceStreak, 4);
    },
  );

  test('physical ranking only appears in top or bottom five', () {
    const middleRanking = PlayerRanking(
      rank: 6,
      totalPlayers: 12,
      score: 8,
      sessionCount: 10,
      playerAheadName: 'Ana',
      sessionsToOvertake: 2,
    );
    const bottomRanking = PlayerRanking(
      rank: 12,
      totalPlayers: 12,
      score: 2,
      sessionCount: 10,
      playerAheadName: 'Ana',
      sessionsToOvertake: 2,
    );
    const global = PlayerRanking(
      rank: 4,
      totalPlayers: 12,
      score: 8,
      sessionCount: 10,
      playerAheadName: 'Ana',
      sessionsToOvertake: 2,
    );

    expect(
      const PlayerMotivationKpis(
        globalRanking: global,
        recentRanking: global,
        physicalRanking: middleRanking,
        recentAttendancePercentage: 80,
        previousAttendancePercentage: 70,
        recentAttendedSessionCount: 8,
        recentEligibleSessionCount: 10,
        recentPunctualityPercentage: 90,
        attendanceStreak: 6,
        absenceStreak: 2,
        bestAttendanceStreak: 8,
      ).shouldShowPhysicalRanking,
      isFalse,
    );
    expect(
      const PlayerMotivationKpis(
        globalRanking: global,
        recentRanking: global,
        physicalRanking: bottomRanking,
        recentAttendancePercentage: 80,
        previousAttendancePercentage: 70,
        recentAttendedSessionCount: 8,
        recentEligibleSessionCount: 10,
        recentPunctualityPercentage: 90,
        attendanceStreak: 6,
        absenceStreak: 2,
        bestAttendanceStreak: 8,
      ).shouldShowPhysicalRanking,
      isTrue,
    );
  });

  test('global ranking compares eligible attendance percentages', () {
    final current = AppUser(
      id: 'new-player',
      email: 'new@example.com',
      fullName: 'Nueva',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
      teamJoinedAt: DateTime(2026, 8, 8),
    );
    const veteran = AppUser(
      id: 'veteran',
      email: 'veteran@example.com',
      fullName: 'Veterana',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
    );
    final sessions = List.generate(
      10,
      (index) => TeamSession(
        id: 'ranking-$index',
        teamId: 'team-1',
        title: 'Sesión $index',
        startTime: DateTime(2026, 8, index + 1, 19),
        endTime: DateTime(2026, 8, index + 1, 20),
      ),
    );
    final attendance = {
      for (var index = 0; index < sessions.length; index++)
        sessions[index].id: {
          veteran.id: AttendanceRecord(
            userId: veteran.id,
            status: index < 8
                ? AttendanceStatus.attending
                : AttendanceStatus.absent,
          ),
        },
    };

    final kpis = buildPlayerMotivationKpis(
      currentPlayer: current,
      members: [current, veteran],
      completedSessions: sessions,
      attendanceBySession: attendance,
      referenceDate: DateTime(2026, 8, 24),
    );

    expect(kpis.globalRanking?.rank, 1);
    expect(kpis.globalRanking?.score, 3);
    expect(kpis.globalRanking?.sessionCount, 3);
    expect(kpis.globalRanking?.percentage, 100);
  });

  testWidgets('renders motivational rankings and progress', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const global = PlayerRanking(
      rank: 4,
      totalPlayers: 12,
      score: 8,
      sessionCount: 10,
      playerAheadName: 'Ana',
      sessionsToOvertake: 2,
    );
    const monthly = PlayerRanking(
      rank: 2,
      totalPlayers: 12,
      score: 3,
      sessionCount: 4,
      playerAheadName: 'Bea',
      sessionsToOvertake: 1,
    );
    const physical = PlayerRanking(
      rank: 12,
      totalPlayers: 12,
      score: 2,
      sessionCount: 10,
      playerAheadName: 'Ana',
      sessionsToOvertake: 2,
    );
    const kpis = PlayerMotivationKpis(
      globalRanking: global,
      recentRanking: monthly,
      physicalRanking: physical,
      recentAttendancePercentage: 80,
      previousAttendancePercentage: 70,
      recentAttendedSessionCount: 8,
      recentEligibleSessionCount: 10,
      recentPunctualityPercentage: 90,
      attendanceStreak: 6,
      absenceStreak: 2,
      bestAttendanceStreak: 8,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: PlayerMotivationCard(teamName: 'Juvenil Masculino', kpis: kpis),
        ),
      ),
    );

    expect(find.text('Tu rendimiento'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('#4'), findsNothing);
    expect(find.text('🔥'), findsNothing);
    expect(find.text('👻'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('toggle-player-kpis')));
    await tester.pumpAndSettle();

    expect(find.text('#4'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('Ranking físico · Bottom 5'), findsOneWidget);
    expect(find.text('🔥'), findsOneWidget);
    expect(find.text('👻'), findsOneWidget);
    expect(find.text('Racha asistiendo'), findsOneWidget);
    expect(find.text('Racha sin asistir'), findsOneWidget);
    expect(find.text('Puntualidad'), findsOneWidget);
    expect(find.text('Mejor racha'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);
    expect(find.text('Últimos 30 días'), findsWidgets);
    expect(find.text('+10 pp'), findsOneWidget);
    expect(find.text('Antes: 70%'), findsOneWidget);
    expect(
      find.text('Estás a 2 entrenamientos de superar a Ana.'),
      findsOneWidget,
    );
  });

  test('streak metrics respect their visibility thresholds', () {
    const ranking = PlayerRanking(
      rank: 1,
      totalPlayers: 1,
      score: 5,
      sessionCount: 5,
      playerAheadName: null,
      sessionsToOvertake: null,
    );
    const hidden = PlayerMotivationKpis(
      globalRanking: ranking,
      recentRanking: ranking,
      physicalRanking: ranking,
      recentAttendancePercentage: 100,
      previousAttendancePercentage: null,
      recentAttendedSessionCount: 5,
      recentEligibleSessionCount: 5,
      recentPunctualityPercentage: 100,
      attendanceStreak: 5,
      absenceStreak: 1,
      bestAttendanceStreak: 5,
    );
    const visible = PlayerMotivationKpis(
      globalRanking: ranking,
      recentRanking: ranking,
      physicalRanking: ranking,
      recentAttendancePercentage: 100,
      previousAttendancePercentage: null,
      recentAttendedSessionCount: 6,
      recentEligibleSessionCount: 6,
      recentPunctualityPercentage: 100,
      attendanceStreak: 6,
      absenceStreak: 2,
      bestAttendanceStreak: 6,
    );

    expect(hidden.shouldShowAttendanceStreak, isFalse);
    expect(hidden.shouldShowAbsenceStreak, isFalse);
    expect(visible.shouldShowAttendanceStreak, isTrue);
    expect(visible.shouldShowAbsenceStreak, isTrue);
  });

  test('injuries do not interrupt an active attendance streak', () {
    const player = AppUser(
      id: 'player',
      email: 'player@example.com',
      fullName: 'Jugador',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
    );
    final sessions = List.generate(
      4,
      (index) => TeamSession(
        id: 'streak-$index',
        teamId: 'team-1',
        title: 'Sesión $index',
        startTime: DateTime(2026, 8, index + 1, 19),
        endTime: DateTime(2026, 8, index + 1, 20),
      ),
    );
    final statuses = [
      AttendanceStatus.absent,
      AttendanceStatus.attending,
      AttendanceStatus.lateUnannounced,
      AttendanceStatus.injured,
    ];
    final kpis = buildPlayerMotivationKpis(
      currentPlayer: player,
      members: const [player],
      completedSessions: sessions,
      attendanceBySession: {
        for (var index = 0; index < sessions.length; index++)
          sessions[index].id: {
            player.id: AttendanceRecord(
              userId: player.id,
              status: statuses[index],
            ),
          },
      },
      referenceDate: DateTime(2026, 8, 24),
    );

    expect(kpis.attendanceStreak, 2);
    expect(kpis.absenceStreak, 0);
    expect(kpis.bestAttendanceStreak, 2);
  });

  test('builds team attendance trend for consecutive thirty-day windows', () {
    const players = [
      AppUser(
        id: 'one',
        email: 'one@example.com',
        fullName: 'Uno',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
      AppUser(
        id: 'two',
        email: 'two@example.com',
        fullName: 'Dos',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
      AppUser(
        id: 'three',
        email: 'three@example.com',
        fullName: 'Tres',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
    ];
    final previousSession = TeamSession(
      id: 'previous',
      teamId: 'team-1',
      title: 'Anterior',
      startTime: DateTime(2026, 7, 10, 19),
      endTime: DateTime(2026, 7, 10, 20),
    );
    final recentSession = TeamSession(
      id: 'recent',
      teamId: 'team-1',
      title: 'Reciente',
      startTime: DateTime(2026, 8, 10, 19),
      endTime: DateTime(2026, 8, 10, 20),
    );
    final trend = buildTeamAttendanceTrend(
      members: players,
      completedSessions: [previousSession, recentSession],
      attendanceBySession: {
        previousSession.id: {
          'one': const AttendanceRecord(
            userId: 'one',
            status: AttendanceStatus.attending,
          ),
          'two': const AttendanceRecord(
            userId: 'two',
            status: AttendanceStatus.absent,
          ),
          'three': const AttendanceRecord(
            userId: 'three',
            status: AttendanceStatus.injured,
          ),
        },
        recentSession.id: {
          'one': const AttendanceRecord(
            userId: 'one',
            status: AttendanceStatus.attending,
          ),
          'two': const AttendanceRecord(
            userId: 'two',
            status: AttendanceStatus.late,
          ),
          'three': const AttendanceRecord(
            userId: 'three',
            status: AttendanceStatus.absent,
          ),
        },
      },
      referenceDate: DateTime(2026, 8, 24),
    );

    expect(trend.recentPercentage, 67);
    expect(trend.previousPercentage, 50);
    expect(trend.seasonPercentage, 60);
    expect(trend.percentagePointChange, 17);
    expect(trend.recentSessionCount, 1);
    expect(trend.activePlayerCount, 3);
    expect(trend.averageAvailablePlayerCount, 2);
    expect(trend.seasonAverageAvailablePlayerCount, 1.5);
    expect(trend.recentAbsenceCount, 1);
    expect(trend.recentLateCount, 1);
  });

  testWidgets('renders coach team percentage and comparison', (tester) async {
    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const trend = TeamAttendanceTrend(
      recentPercentage: 86,
      previousPercentage: 79,
      seasonPercentage: 82,
      activePlayerCount: 14,
      recentSessionCount: 8,
      averageAvailablePlayerCount: 11.5,
      seasonAverageAvailablePlayerCount: 10.8,
      recentAbsenceCount: 3,
      recentLateCount: 2,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: CoachTeamPerformanceCard(
            teamName: 'Juvenil Masculino',
            trend: trend,
          ),
        ),
      ),
    );

    expect(find.text('Estado del equipo'), findsOneWidget);
    expect(find.text('86%'), findsOneWidget);
    expect(find.text('Juvenil Masculino · 14 jugadores'), findsOneWidget);
    expect(find.text('+7 pp'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('toggle-coach-kpis')));
    await tester.pumpAndSettle();

    expect(find.text('+7 pp'), findsOneWidget);
    expect(find.text('Antes: 79%'), findsOneWidget);
    expect(find.text('Media 30 días'), findsOneWidget);
    expect(find.text('11,5'), findsOneWidget);
    expect(find.text('Media temporada'), findsOneWidget);
    expect(find.text('10,8'), findsOneWidget);
    expect(find.text('Asistencia temporada'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    expect(find.text('Ausencias'), findsOneWidget);
    expect(find.text('Retrasos'), findsOneWidget);
  });
}
