import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/models/player_tag.dart';
import 'package:mi_asistencia/src/screens/manage_team_screen.dart';
import 'package:mi_asistencia/src/theme/app_theme.dart';
import 'package:mi_asistencia/src/widgets/player_tag_editor.dart';

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
        TeamMemberAction.editTags,
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
        TeamMemberAction.editTags,
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
      [
        TeamMemberAction.editTags,
        TeamMemberAction.presumeAbsent,
        TeamMemberAction.remove,
      ],
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

  test('only players can be tagged', () {
    expect(
      availableTeamMemberActions(
        currentUser: owner,
        member: player,
        team: team,
      ),
      contains(TeamMemberAction.editTags),
    );
    expect(
      availableTeamMemberActions(currentUser: owner, member: coach, team: team),
      isNot(contains(TeamMemberAction.editTags)),
    );
  });

  testWidgets('player card shows the assigned tags', (tester) async {
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
            tags: const [
              PlayerTag(id: 'gk', name: 'Portero'),
              PlayerTag(id: 'left', name: 'Zurdo'),
              PlayerTag(id: 'cap', name: 'Capitán'),
            ],
            tagAssignments: const {
              'player': ['gk', 'left', 'deleted-tag'],
            },
          ),
        ),
      ),
    );

    expect(find.text('Portero'), findsOneWidget);
    expect(find.text('Zurdo'), findsOneWidget);
    expect(find.text('Capitán'), findsNothing);
    expect(find.byIcon(Icons.label_outline), findsNWidgets(2));
  });

  group('player tag editor', () {
    final catalog = [
      for (var index = 1; index <= 7; index++)
        PlayerTag(id: 'tag-$index', name: 'Etiqueta $index'),
    ];

    Future<void> pumpEditor(
      WidgetTester tester, {
      required List<String> initialTagIds,
      Future<void> Function(List<String>, List<PlayerTag>)? onSave,
      Future<PlayerTag> Function(String, List<PlayerTag>)? onCreateTag,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PlayerTagEditor(
              playerName: 'Marina García',
              catalog: catalog,
              initialTagIds: initialTagIds,
              onCreateTag:
                  onCreateTag ??
                  (name, _) async => PlayerTag(id: 'new', name: name),
              onSave: onSave ?? (_, _) async {},
            ),
          ),
        ),
      );
    }

    FilterChip chip(WidgetTester tester, String id) =>
        tester.widget(find.byKey(ValueKey('player-tag-chip-$id')));

    testWidgets('disables unselected tags at the limit', (tester) async {
      await pumpEditor(
        tester,
        initialTagIds: ['tag-1', 'tag-2', 'tag-3', 'tag-4'],
      );

      expect(find.text('4/5'), findsOneWidget);
      expect(find.text('Máximo 5 etiquetas'), findsNothing);
      expect(chip(tester, 'tag-6').onSelected, isNotNull);

      await tester.tap(find.byKey(const ValueKey('player-tag-chip-tag-5')));
      await tester.pump();

      expect(find.text('5/5'), findsOneWidget);
      expect(find.text('Máximo 5 etiquetas'), findsOneWidget);
      expect(chip(tester, 'tag-6').onSelected, isNull);
      expect(chip(tester, 'tag-7').onSelected, isNull);
      expect(chip(tester, 'tag-1').onSelected, isNotNull);

      await tester.tap(find.byKey(const ValueKey('player-tag-chip-tag-1')));
      await tester.pump();

      expect(find.text('4/5'), findsOneWidget);
      expect(chip(tester, 'tag-6').onSelected, isNotNull);
    });

    testWidgets('saves the selected tag ids', (tester) async {
      List<String>? savedIds;
      await pumpEditor(
        tester,
        initialTagIds: ['tag-2', 'unknown'],
        onSave: (tagIds, _) async => savedIds = tagIds,
      );

      expect(find.text('1/5'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('player-tag-chip-tag-4')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('player-tag-save')));
      await tester.pump();

      expect(savedIds, ['tag-2', 'tag-4']);
    });

    testWidgets('selects a tag created inline', (tester) async {
      List<String>? savedIds;
      List<PlayerTag>? savedCatalog;
      await pumpEditor(
        tester,
        initialTagIds: ['tag-1'],
        onCreateTag: (name, existing) async =>
            PlayerTag(id: 'created', name: name),
        onSave: (tagIds, latestCatalog) async {
          savedIds = tagIds;
          savedCatalog = latestCatalog;
        },
      );

      await tester.enterText(
        find.byKey(const ValueKey('player-tag-new-name')),
        '  Zurdo ',
      );
      await tester.tap(find.byKey(const ValueKey('player-tag-add')));
      await tester.pump();

      expect(find.text('Zurdo'), findsOneWidget);
      expect(find.text('2/5'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('player-tag-save')));
      await tester.pump();

      expect(savedIds, unorderedEquals(['tag-1', 'created']));
      expect(savedCatalog!.map((tag) => tag.id), contains('created'));
    });
  });

  group('PlayerTagMembersEditor', () {
    const tag = PlayerTag(id: 'gk', name: 'Portero');
    const players = <TagMemberOption>[
      (id: 'ana', name: 'Ana', atLimit: false),
      (id: 'bea', name: 'Bea', atLimit: false),
      (id: 'eva', name: 'Eva', atLimit: true),
    ];

    Future<void> pumpMembersEditor(
      WidgetTester tester, {
      Future<void> Function(Set<String>, Set<String>)? onSave,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PlayerTagMembersEditor(
              tag: tag,
              players: players,
              initialMemberIds: const {'ana'},
              onSave: onSave ?? (_, _) async {},
            ),
          ),
        ),
      );
    }

    CheckboxListTile tile(WidgetTester tester, String id) =>
        tester.widget(find.byKey(ValueKey('tag-member-$id')));

    testWidgets('players at the tag limit cannot be checked', (tester) async {
      await pumpMembersEditor(tester);

      expect(tile(tester, 'ana').value, isTrue);
      expect(tile(tester, 'bea').onChanged, isNotNull);
      expect(tile(tester, 'eva').onChanged, isNull);
      expect(find.text('Ya tiene 5 etiquetas'), findsOneWidget);
    });

    testWidgets('save is disabled until something changes', (tester) async {
      await pumpMembersEditor(tester);

      final save = find.byKey(const ValueKey('tag-members-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('tag-member-bea')));
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    });

    testWidgets('saves only the players that changed', (tester) async {
      Set<String>? added;
      Set<String>? removed;
      await pumpMembersEditor(
        tester,
        onSave: (a, r) async {
          added = a;
          removed = r;
        },
      );

      await tester.tap(find.byKey(const ValueKey('tag-member-bea')));
      await tester.tap(find.byKey(const ValueKey('tag-member-ana')));
      await tester.pump();
      expect(find.text('1 seleccionado'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tag-members-save')));
      await tester.pump();
      expect(added, {'bea'});
      expect(removed, {'ana'});
    });
  });
}
