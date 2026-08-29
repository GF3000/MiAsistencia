import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/app.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/models/attendance.dart';
import 'package:mi_asistencia/src/models/team_membership.dart';
import 'package:mi_asistencia/src/models/team_session.dart';
import 'package:mi_asistencia/src/providers.dart';
import 'package:mi_asistencia/src/repositories/auth_repository.dart';
import 'package:mi_asistencia/src/repositories/team_repository.dart';
import 'package:mi_asistencia/src/router/gate_state.dart';
import 'package:mi_asistencia/src/screens/auth_screen.dart';
import 'package:mi_asistencia/src/screens/batch_attendance_screen.dart';
import 'package:mi_asistencia/src/screens/batch_edit_sessions_screen.dart';
import 'package:mi_asistencia/src/screens/create_session_screen.dart';
import 'package:mi_asistencia/src/screens/edit_session_screen.dart';
import 'package:mi_asistencia/src/screens/session_detail_screen.dart';
import 'package:mi_asistencia/src/screens/team_invitation_screen.dart';
import 'package:mi_asistencia/src/utils/team_invitation.dart';
import 'package:mi_asistencia/src/widgets/team_calendar.dart';

void main() {
  testWidgets('renders the Spanish application shell', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gateStateProvider.overrideWithValue(const GateSignedOut()),
        ],
        child: const MiAsistenciaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Iniciar sesión'), findsOneWidget);
  });

  testWidgets('offers password recovery on sign-in', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AuthScreen())),
    );

    expect(find.text('Continuar con Google'), findsNothing);
    expect(find.text('He olvidado mi contraseña'), findsOneWidget);

    await tester.ensureVisible(find.text('He olvidado mi contraseña'));
    await tester.tap(find.text('He olvidado mi contraseña'));
    await tester.pumpAndSettle();

    expect(find.text('Recuperar contraseña'), findsOneWidget);
    expect(find.text('Enviar enlace'), findsOneWidget);
    expect(
      find.text('Te enviaremos un enlace para crear otra contraseña.'),
      findsOneWidget,
    );
  });

  testWidgets('hides Google and password recovery during registration', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AuthScreen())),
    );

    await tester.ensureVisible(find.text('Quiero crear una cuenta'));
    await tester.tap(find.text('Quiero crear una cuenta'));
    await tester.pump();

    expect(find.text('Crear cuenta'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsNothing);
    expect(find.text('He olvidado mi contraseña'), findsNothing);
  });

  test('describes Google authentication errors in Spanish', () {
    expect(
      authErrorMessage(FirebaseAuthException(code: 'popup-blocked')),
      contains('ventana de Google'),
    );
    expect(
      authErrorMessage(
        FirebaseAuthException(code: 'account-exists-with-different-credential'),
      ),
      contains('método que usaste originalmente'),
    );
  });

  test('generates a readable six-character team code', () {
    final code = generateTeamCode(Random(7));

    expect(code, hasLength(6));
    expect(code, matches(RegExp(r'^[A-HJ-KM-NP-Z2-9]{6}$')));
    expect(code, isNot(matches(RegExp(r'[01OIL]'))));
  });

  test('normalizes valid invitation codes and rejects ambiguous ones', () {
    expect(normalizeTeamCode(' abc234 '), 'ABC234');
    expect(normalizeTeamCode('ABC01L'), isNull);
    expect(normalizeTeamCode('short'), isNull);
  });

  test('builds a shareable team invitation URL', () {
    final url = buildTeamInviteUrl(
      'ABC234',
      baseUri: Uri.parse(
        'https://miasistencia-bmcoras.web.app/dashboard?old=value#section',
      ),
    );

    expect(url, 'https://miasistencia-bmcoras.web.app/?join=ABC234');
  });

  testWidgets('explains a pending invitation before authentication', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          teamInvitationNameProvider(
            'ABC234',
          ).overrideWith((ref) async => 'Halcones Senior'),
        ],
        child: const MaterialApp(
          home: AuthScreen(invitationCode: 'ABC234'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('pending-team-invitation')),
      findsOneWidget,
    );
    expect(find.textContaining('Halcones Senior'), findsOneWidget);
    expect(find.textContaining('ABC234'), findsNothing);
  });

  testWidgets('rejects an invalid invitation before loading authentication', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InvitationMessageScreen(
          message: 'El enlace de invitación no contiene un código válido.',
          onContinue: () {},
        ),
      ),
    );

    expect(
      find.text('El enlace de invitación no contiene un código válido.'),
      findsOneWidget,
    );
  });

  testWidgets('asks a player to confirm before adding a team', (tester) async {
    var confirmed = false;
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: TeamSwitchPrompt(
          currentTeamName: 'Equipo X',
          targetTeamName: 'Equipo Y',
          busy: false,
          onCancel: () => cancelled = true,
          onConfirm: () => confirmed = true,
        ),
      ),
    );

    expect(find.text('¿Añadir equipo?'), findsOneWidget);
    expect(
      find.textContaining(
        'Actualmente perteneces a Equipo X. ¿Quieres unirte también a '
        'Equipo Y?',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Añadir equipo'));
    expect(confirmed, isTrue);
    expect(cancelled, isFalse);
  });

  testWidgets('coach roster previews a player note on one line', (
    tester,
  ) async {
    const member = AppUser(
      id: 'player-note',
      email: 'player@example.com',
      fullName: 'Jugador con nota',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
    );
    const record = AttendanceRecord(
      userId: 'player-note',
      status: AttendanceStatus.late,
      note:
          'Llegaré aproximadamente veinte minutos tarde por una reunión de '
          'trabajo.',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoachAttendanceListItem(
            member: member,
            record: record,
            updateLabel: 'Actualizado a las 18:30',
            onTap: () {},
          ),
        ),
      ),
    );

    final preview = tester.widget<Text>(
      find.byKey(const ValueKey('coach-note-preview-player-note')),
    );
    expect(preview.data, startsWith('Nota: Llegaré'));
    expect(preview.maxLines, 1);
    expect(preview.overflow, TextOverflow.ellipsis);
  });

  test('builds recurring occurrences on selected weekdays', () {
    final occurrences = buildSessionOccurrences(
      firstDate: DateTime(2026, 8, 24),
      startTime: DateTime(2000, 1, 1, 19),
      endTime: DateTime(2000, 1, 1, 20, 30),
      weekdays: {DateTime.monday, DateTime.wednesday},
      weeks: 2,
    );

    expect(occurrences, hasLength(4));
    expect(
      occurrences.map((occurrence) => occurrence.start.weekday),
      everyElement(isIn([DateTime.monday, DateTime.wednesday])),
    );
    expect(occurrences.first.start.hour, 19);
    expect(occurrences.first.end.minute, 30);
  });

  test('players can only edit attendance before a session ends', () {
    final session = TeamSession(
      id: 'session-1',
      teamId: 'team-1',
      title: 'Entrenamiento',
      startTime: DateTime(2026, 8, 23, 19),
      endTime: DateTime(2026, 8, 23, 20, 30),
    );

    expect(
      canPlayerEditAttendance(session, at: DateTime(2026, 8, 23, 20, 29)),
      isTrue,
    );
    expect(
      canPlayerEditAttendance(session, at: DateTime(2026, 8, 23, 20, 30)),
      isFalse,
    );
    expect(
      canPlayerEditAttendance(session, at: DateTime(2026, 8, 24)),
      isFalse,
    );
  });

  test('editing a session preserves its identity and recurrence series', () {
    final session = TeamSession(
      id: 'session-1',
      teamId: 'team-1',
      title: 'Entrenamiento',
      startTime: DateTime(2026, 8, 24, 19),
      endTime: DateTime(2026, 8, 24, 20, 30),
      recurrenceSeriesId: 'series-1',
    );

    final updated = session.copyWith(
      title: 'Partido amistoso',
      startTime: DateTime(2026, 8, 25, 18),
      endTime: DateTime(2026, 8, 25, 20),
    );

    expect(updated.id, session.id);
    expect(updated.teamId, session.teamId);
    expect(updated.recurrenceSeriesId, 'series-1');
    expect(updated.title, 'Partido amistoso');
    expect(updated.startTime, DateTime(2026, 8, 25, 18));
  });

  testWidgets('session edit screen is prefilled with current values', (
    tester,
  ) async {
    final session = TeamSession(
      id: 'session-1',
      teamId: 'team-1',
      title: 'Entrenamiento de tiro',
      startTime: DateTime(2026, 8, 24, 19),
      endTime: DateTime(2026, 8, 24, 20, 30),
      recurrenceSeriesId: 'series-1',
    );

    const membership = TeamMembership(
      teamId: 'team-1',
      memberId: 'coach-1',
      userId: 'coach-1',
      fullName: 'Entrenador',
      email: 'coach@example.com',
      role: UserRole.admin,
      active: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentMembershipProvider.overrideWithValue(membership),
          teamSessionsProvider('team-1').overrideWith(
            (ref) => Stream.value([session]),
          ),
        ],
        child: const MaterialApp(
          home: EditSessionScreen(sessionId: 'session-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Editar sesión'), findsOneWidget);
    expect(find.text('Entrenamiento de tiro'), findsOneWidget);
    expect(find.textContaining('Solo se editará esta sesión'), findsOneWidget);
  });

  test('defaults missing attendance to attending', () {
    final record = AttendanceRecord.attending('player-1');

    expect(record.status, AttendanceStatus.attending);
    expect(record.status.playerLabel, 'Asisto');
    expect(record.status.coachLabel, 'Asiste');
    expect(record.updatedAt, isNull);
  });

  test('attendance presumption follows its effective history', () {
    final player = AppUser(
      id: 'player-1',
      email: 'player@example.com',
      fullName: 'Jugador',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
      attendancePresumption: AttendancePresumption.attending,
      attendancePresumptionHistory: [
        AttendancePresumptionChange(
          value: AttendancePresumption.absent,
          effectiveFrom: DateTime(2026, 8, 25),
        ),
        AttendancePresumptionChange(
          value: AttendancePresumption.attending,
          effectiveFrom: DateTime(2026, 9, 10),
        ),
      ],
    );

    expect(
      resolveAttendanceStatus(
        user: player,
        explicitRecord: null,
        sessionTime: DateTime(2026, 8, 24),
      ),
      AttendanceStatus.attending,
    );
    expect(
      resolveAttendanceStatus(
        user: player,
        explicitRecord: null,
        sessionTime: DateTime(2026, 8, 26),
      ),
      AttendanceStatus.absent,
    );
    expect(
      resolveAttendanceStatus(
        user: player,
        explicitRecord: null,
        sessionTime: DateTime(2026, 9, 11),
      ),
      AttendanceStatus.attending,
    );
  });

  test('explicit attendance overrides the player presumption', () {
    const player = AppUser(
      id: 'player-1',
      email: 'player@example.com',
      fullName: 'Jugador',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
      attendancePresumption: AttendancePresumption.absent,
    );
    const explicit = AttendanceRecord(
      userId: 'player-1',
      status: AttendanceStatus.courtOnly,
    );

    expect(
      resolveAttendanceStatus(
        user: player,
        explicitRecord: explicit,
        sessionTime: DateTime(2026, 8, 24),
      ),
      AttendanceStatus.courtOnly,
    );
  });

  test('attendance labels match the viewer perspective', () {
    expect(AttendanceStatus.attending.playerLabel, 'Asisto');
    expect(AttendanceStatus.attending.coachLabel, 'Asiste');
    expect(AttendanceStatus.absent.playerLabel, 'No asisto');
    expect(AttendanceStatus.absent.coachLabel, 'No asiste');
    expect(AttendanceStatus.late.playerLabel, 'Llego tarde');
    expect(AttendanceStatus.late.coachLabel, 'Llega tarde');
    expect(AttendanceStatus.injured.playerLabel, 'Lesión');
    expect(AttendanceStatus.injured.coachLabel, 'Lesionado');
  });

  test('uses coach terminology for the management role', () {
    expect(UserRole.admin.label, 'Entrenador');
    expect(UserRole.admin.isCoach, isTrue);
  });

  test('only a player assigned to a team can leave it', () {
    const player = AppUser(
      id: 'player',
      email: 'player@example.com',
      fullName: 'Jugador',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
    );
    const coach = AppUser(
      id: 'coach',
      email: 'coach@example.com',
      fullName: 'Entrenador',
      role: UserRole.admin,
      teamId: 'team-1',
      active: true,
    );
    const playerWithoutTeam = AppUser(
      id: 'new-player',
      email: 'new@example.com',
      fullName: 'Jugador nuevo',
      role: UserRole.player,
      teamId: null,
      active: true,
    );

    expect(player.canLeaveTeam, isTrue);
    expect(coach.canLeaveTeam, isFalse);
    expect(playerWithoutTeam.canLeaveTeam, isFalse);
  });

  test('counts only players whose status represents attendance', () {
    const players = [
      AppUser(
        id: 'all',
        email: 'all@example.com',
        fullName: 'Todo',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
      AppUser(
        id: 'court',
        email: 'court@example.com',
        fullName: 'Pista',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
      AppUser(
        id: 'late',
        email: 'late@example.com',
        fullName: 'Tarde',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
      AppUser(
        id: 'late-unannounced',
        email: 'late-unannounced@example.com',
        fullName: 'Tarde sin avisar',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
      AppUser(
        id: 'gym',
        email: 'gym@example.com',
        fullName: 'Físico',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
      AppUser(
        id: 'coach',
        email: 'coach@example.com',
        fullName: 'Entrenador',
        role: UserRole.admin,
        teamId: 'team-1',
        active: true,
      ),
    ];
    final attendance = {
      'court': const AttendanceRecord(
        userId: 'court',
        status: AttendanceStatus.courtOnly,
      ),
      'late': const AttendanceRecord(
        userId: 'late',
        status: AttendanceStatus.late,
      ),
      'gym': const AttendanceRecord(
        userId: 'gym',
        status: AttendanceStatus.gymOnly,
      ),
      'late-unannounced': const AttendanceRecord(
        userId: 'late-unannounced',
        status: AttendanceStatus.lateUnannounced,
      ),
    };

    expect(
      countAttendingPlayers(
        members: players,
        attendance: attendance,
        sessionTime: DateTime(2026, 8, 24),
      ),
      4,
    );
  });

  test('builds coach summary for court physical and late players', () {
    const players = [
      AppUser(
        id: 'all',
        email: 'all@example.com',
        fullName: 'Ana',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
      AppUser(
        id: 'court',
        email: 'court@example.com',
        fullName: 'Bruno',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
      AppUser(
        id: 'gym',
        email: 'gym@example.com',
        fullName: 'Carla',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
      AppUser(
        id: 'late',
        email: 'late@example.com',
        fullName: 'Diego',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
      AppUser(
        id: 'late-unannounced',
        email: 'late2@example.com',
        fullName: 'Elena',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
      ),
    ];
    final attendance = {
      'court': const AttendanceRecord(
        userId: 'court',
        status: AttendanceStatus.courtOnly,
      ),
      'gym': const AttendanceRecord(
        userId: 'gym',
        status: AttendanceStatus.gymOnly,
      ),
      'late': const AttendanceRecord(
        userId: 'late',
        status: AttendanceStatus.late,
      ),
      'late-unannounced': const AttendanceRecord(
        userId: 'late-unannounced',
        status: AttendanceStatus.lateUnannounced,
      ),
    };

    final summary = buildCoachAttendanceSummary(
      members: players,
      attendance: attendance,
      sessionTime: DateTime(2026, 8, 24),
    );

    expect(summary.courtCount, 4);
    expect(summary.physicalCount, 4);
    expect(summary.totalPlayers, 5);
    expect(summary.latePlayerNames, ['Diego', 'Elena']);
  });

  test('coach-only attendance incidents are excluded from player options', () {
    expect(
      AttendanceStatus.coachOnlyOptions.map((status) => status.coachLabel),
      containsAll([
        'Llega tarde sin avisar',
        'Falta sin avisar',
        'Avisa tarde de que no viene',
      ]),
    );
    expect(
      AttendanceStatus.playerOptions.any((status) => status.isCoachOnly),
      isFalse,
    );
    expect(
      AttendanceStatus.fromFirestore('absent_unannounced'),
      AttendanceStatus.absentUnannounced,
    );
  });

  testWidgets('batch edit offers independent name and time changes', (
    tester,
  ) async {
    final sessions = [
      TeamSession(
        id: 'session-1',
        teamId: 'team-1',
        title: 'Entrenamiento',
        startTime: DateTime(2026, 8, 24, 19),
        endTime: DateTime(2026, 8, 24, 20, 30),
      ),
      TeamSession(
        id: 'session-2',
        teamId: 'team-1',
        title: 'Entrenamiento',
        startTime: DateTime(2026, 8, 26, 19),
        endTime: DateTime(2026, 8, 26, 20, 30),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: BatchEditSessionsScreen(sessions: sessions)),
      ),
    );

    expect(find.text('Modificar 2 sesiones'), findsOneWidget);
    await tester.tap(find.text('Cambiar nombre'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('batch-session-title')), findsOneWidget);

    await tester.tap(find.text('Cambiar horario'));
    await tester.pumpAndSettle();
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Fin'), findsOneWidget);
  });

  testWidgets('selected player sessions start checked in batch attendance', (
    tester,
  ) async {
    const user = TeamMembership(
      teamId: 'team-1',
      memberId: 'player',
      userId: 'player',
      fullName: 'Jugador',
      email: 'player@example.com',
      role: UserRole.player,
      active: true,
    );
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final sessions = [
      TeamSession(
        id: 'session-1',
        teamId: 'team-1',
        title: 'Entrenamiento 1',
        startTime: tomorrow,
        endTime: tomorrow.add(const Duration(hours: 1)),
      ),
      TeamSession(
        id: 'session-2',
        teamId: 'team-1',
        title: 'Entrenamiento 2',
        startTime: tomorrow.add(const Duration(days: 1)),
        endTime: tomorrow.add(const Duration(days: 1, hours: 1)),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentMembershipProvider.overrideWithValue(user),
        ],
        child: MaterialApp(
          home: BatchAttendanceScreen(
            sessions: sessions,
            initiallySelectAll: true,
          ),
        ),
      ),
    );

    final checkboxes = tester.widgetList<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(checkboxes, hasLength(2));
    expect(checkboxes.every((checkbox) => checkbox.value == true), isTrue);

    final continueButton = find.byKey(
      const ValueKey('change-batch-attendance'),
    );
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(find.text('Estado y nota'), findsOneWidget);
    expect(find.text('El cambio se aplicará a 2 sesiones.'), findsOneWidget);
  });

  testWidgets('preselected sessions open attendance details without filters', (
    tester,
  ) async {
    const user = AppUser(
      id: 'player',
      email: 'player@example.com',
      fullName: 'Jugador',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
    );
    final session = TeamSession(
      id: 'session-1',
      teamId: 'team-1',
      title: 'Entrenamiento',
      startTime: DateTime.now().add(const Duration(days: 1)),
      endTime: DateTime.now().add(const Duration(days: 1, hours: 1)),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showBatchAttendanceEditor(
                  context: context,
                  user: user,
                  sessions: [session],
                ),
                child: const Text('Abrir asistencia'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir asistencia'));
    await tester.pumpAndSettle();

    expect(find.text('Estado y nota'), findsOneWidget);
    expect(find.text('El cambio se aplicará a 1 sesión.'), findsOneWidget);
    expect(find.text('Selecciona por período'), findsNothing);
    expect(find.text('Próximos 7 días'), findsNothing);
    expect(find.text('Próximos 30 días'), findsNothing);
  });

  test('batch attendance filters by rolling days and weekday', () {
    final sessions = [
      TeamSession(
        id: 'today',
        teamId: 'team-1',
        title: 'Hoy',
        startTime: DateTime(2026, 8, 24, 19),
        endTime: DateTime(2026, 8, 24, 20),
      ),
      TeamSession(
        id: 'monday',
        teamId: 'team-1',
        title: 'Lunes',
        startTime: DateTime(2026, 8, 31, 19),
        endTime: DateTime(2026, 8, 31, 20),
      ),
      TeamSession(
        id: 'tuesday',
        teamId: 'team-1',
        title: 'Martes',
        startTime: DateTime(2026, 9, 1, 19),
        endTime: DateTime(2026, 9, 1, 20),
      ),
      TeamSession(
        id: 'next-tuesday',
        teamId: 'team-1',
        title: 'Otro martes',
        startTime: DateTime(2026, 9, 8, 19),
        endTime: DateTime(2026, 9, 8, 20),
      ),
      TeamSession(
        id: 'october',
        teamId: 'team-1',
        title: 'Octubre',
        startTime: DateTime(2026, 10, 1, 19),
        endTime: DateTime(2026, 10, 1, 20),
      ),
    ];

    expect(
      sessionsInNextDays(
        sessions,
        days: 7,
        from: DateTime(2026, 8, 24),
      ).map((session) => session.id),
      ['today'],
    );
    expect(
      sessionsInNextDays(
        sessions,
        days: 30,
        from: DateTime(2026, 8, 24),
      ).map((session) => session.id),
      ['today', 'monday', 'tuesday', 'next-tuesday'],
    );
    expect(
      sessionsOnWeekday(
        sessions,
        DateTime.tuesday,
      ).map((session) => session.id),
      ['tuesday', 'next-tuesday'],
    );
  });

  testWidgets('calendar opens the only session on a selected day', (
    tester,
  ) async {
    final session = TeamSession(
      id: 'session-1',
      teamId: 'team-1',
      title: 'Entrenamiento de tiro',
      startTime: DateTime(2026, 8, 24, 19),
      endTime: DateTime(2026, 8, 24, 20, 30),
    );
    TeamSession? openedSession;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeamCalendarView(
              initialDate: DateTime(2026, 8, 23),
              sessions: [session],
              onSessionSelected: (session) => openedSession = session,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Agosto 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-compact-layout')), findsOne);
    expect(find.text('Entrenamiento de tiro'), findsNothing);

    final sessionDay = find.byKey(const ValueKey('calendar-day-2026-08-24'));
    await tester.ensureVisible(sessionDay);
    await tester.tap(sessionDay);
    await tester.pumpAndSettle();

    expect(openedSession, same(session));
  });

  testWidgets('calendar asks which session to open when a day has several', (
    tester,
  ) async {
    final earlySession = TeamSession(
      id: 'early',
      teamId: 'team-1',
      title: 'Sesión temprana',
      startTime: DateTime(2026, 8, 24, 18),
      endTime: DateTime(2026, 8, 24, 19),
    );
    final lateSession = TeamSession(
      id: 'late',
      teamId: 'team-1',
      title: 'Sesión tardía',
      startTime: DateTime(2026, 8, 24, 20),
      endTime: DateTime(2026, 8, 24, 21),
    );
    TeamSession? openedSession;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeamCalendarView(
              initialDate: DateTime(2026, 8, 23),
              sessions: [lateSession, earlySession],
              onSessionSelected: (session) => openedSession = session,
            ),
          ),
        ),
      ),
    );

    final sessionDay = find.byKey(const ValueKey('calendar-day-2026-08-24'));
    await tester.ensureVisible(sessionDay);
    await tester.tap(sessionDay);
    await tester.pumpAndSettle();

    expect(find.text('Elige una sesión'), findsOneWidget);
    expect(find.text('Sesión temprana'), findsWidgets);
    expect(find.text('Sesión tardía'), findsWidgets);
    expect(openedSession, isNull);

    await tester.tap(
      find.byKey(const ValueKey('calendar-session-option-late')),
    );
    await tester.pumpAndSettle();

    expect(openedSession, same(lateSession));
  });

  testWidgets('calendar starts a new session on an empty selected day', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: SingleChildScrollView(
                child: TeamCalendarView(
                  initialDate: DateTime(2026, 8, 23),
                  sessions: const [],
                  onSessionSelected: (_) {},
                  onEmptyDateSelected: (date) => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          CreateSessionScreen(initialDate: date),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final emptyDay = find.byKey(const ValueKey('calendar-day-2026-08-24'));
    await tester.ensureVisible(emptyDay);
    await tester.tap(emptyDay);
    await tester.pumpAndSettle();

    expect(find.text('Nueva sesión'), findsOneWidget);
    expect(find.text('lunes, 24 de agosto'), findsOneWidget);
  });

  testWidgets('calendar fills the available desktop width', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: 900,
                child: TeamCalendarView(
                  initialDate: DateTime(2026, 8, 23),
                  sessions: const [],
                  onSessionSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('calendar-wide-layout')), findsOneWidget);
    final calendarSize = tester.getSize(
      find.byKey(const ValueKey('calendar-month-card')),
    );
    expect(calendarSize.width, greaterThan(850));
    expect(calendarSize.height, lessThan(500));
  });
}
