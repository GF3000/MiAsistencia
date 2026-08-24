import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/screens/manage_team_screen.dart';
import 'package:mi_asistencia/src/theme/app_theme.dart';

void main() {
  const team = Team(
    id: 'team-1',
    name: 'Equipo principal',
    joinCode: 'ABC234',
    createdBy: 'owner',
  );
  const owner = AppUser(
    id: 'owner',
    email: 'owner@example.com',
    fullName: 'Entrenador Principal',
    role: UserRole.admin,
    teamId: 'team-1',
    active: true,
  );
  const coach = AppUser(
    id: 'coach',
    email: 'coach@example.com',
    fullName: 'Segundo Entrenador',
    role: UserRole.admin,
    teamId: 'team-1',
    active: true,
  );
  const player = AppUser(
    id: 'player',
    email: 'player@example.com',
    fullName: 'Marina García',
    role: UserRole.player,
    teamId: 'team-1',
    active: true,
  );
  const managedPlayer = AppUser(
    id: 'managed-player',
    email: '',
    fullName: 'Jugador sin móvil',
    role: UserRole.player,
    teamId: 'team-1',
    active: true,
    managedByCoach: true,
  );

  test('owner can promote players and manage other coaches', () {
    expect(
      availableTeamMemberActions(
        currentUser: owner,
        member: player,
        team: team,
      ),
      [
        TeamMemberAction.makeCoach,
        TeamMemberAction.presumeAbsent,
        TeamMemberAction.remove,
      ],
    );
    expect(
      availableTeamMemberActions(currentUser: owner, member: coach, team: team),
      [TeamMemberAction.makePlayer, TeamMemberAction.remove],
    );
  });

  test('owner and current user cannot be modified', () {
    expect(
      availableTeamMemberActions(currentUser: coach, member: owner, team: team),
      isEmpty,
    );
    expect(
      availableTeamMemberActions(currentUser: coach, member: coach, team: team),
      isEmpty,
    );
    expect(
      availableTeamMemberActions(
        currentUser: player,
        member: coach,
        team: team,
      ),
      isEmpty,
    );
  });

  testWidgets('player card exposes promotion and removal actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TeamMemberCard(
            member: player,
            currentUser: owner,
            team: team,
            busy: false,
            onAction: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Marina García'), findsOneWidget);
    expect(find.text('Jugador'), findsOneWidget);
    expect(find.text('Por defecto: Asiste'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('member-actions-player')));
    await tester.pumpAndSettle();

    expect(find.text('Hacer entrenador'), findsOneWidget);
    expect(find.text('Presumir no asistencia'), findsOneWidget);
    expect(find.text('Expulsar del equipo'), findsOneWidget);
  });

  testWidgets('team management header exposes the invitation code action', (
    tester,
  ) async {
    var invitationOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TeamManagementHeader(
            team: team,
            coachCount: 2,
            playerCount: 8,
            onShowInvitation: () => invitationOpened = true,
          ),
        ),
      ),
    );

    expect(find.text('Código ABC234'), findsOneWidget);
    expect(find.byTooltip('Ver y compartir código'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('show-team-invitation')));
    expect(invitationOpened, isTrue);
  });

  test('absent-by-default player can be restored to attendance', () {
    const absentPlayer = AppUser(
      id: 'absent-player',
      email: 'absent@example.com',
      fullName: 'Jugador ausente',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
      attendancePresumption: AttendancePresumption.absent,
    );

    expect(
      availableTeamMemberActions(
        currentUser: owner,
        member: absentPlayer,
        team: team,
      ),
      [
        TeamMemberAction.makeCoach,
        TeamMemberAction.presumeAttending,
        TeamMemberAction.remove,
      ],
    );
  });

  test('managed players cannot be promoted to coach', () {
    expect(managedPlayer.hasAccount, isFalse);
    expect(managedPlayer.canLeaveTeam, isFalse);
    expect(
      availableTeamMemberActions(
        currentUser: owner,
        member: managedPlayer,
        team: team,
      ),
      [TeamMemberAction.presumeAbsent, TeamMemberAction.remove],
    );
  });

  testWidgets('managed player card identifies the accountless player', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TeamMemberCard(
            member: managedPlayer,
            currentUser: owner,
            team: team,
            busy: false,
            onAction: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Jugador sin móvil'), findsOneWidget);
    expect(find.text('Sin cuenta'), findsOneWidget);
    expect(find.text('Gestionado por entrenador'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('member-actions-managed-player')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hacer entrenador'), findsNothing);
    expect(find.text('Presumir no asistencia'), findsOneWidget);
    expect(find.text('Expulsar del equipo'), findsOneWidget);
  });

  testWidgets('managed player dialog releases its field after closing', (
    tester,
  ) async {
    String? submittedName;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                submittedName = await showManagedPlayerNameDialog(context);
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('managed-player-name')),
      '  Alex Pérez  ',
    );
    await tester.tap(find.byKey(const ValueKey('confirm-add-managed-player')));
    await tester.pumpAndSettle();

    expect(submittedName, 'Alex Pérez');
    expect(find.byKey(const ValueKey('managed-player-name')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
