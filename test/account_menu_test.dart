import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/models/attendance.dart';
import 'package:mi_asistencia/src/models/team_membership.dart';
import 'package:mi_asistencia/src/providers.dart';
import 'package:mi_asistencia/src/repositories/attendance_repository.dart';
import 'package:mi_asistencia/src/repositories/team_repository.dart';
import 'package:mi_asistencia/src/screens/dashboard_screen.dart';

void main() {
  testWidgets('account actions are distinct and require confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const user = TeamMembership(
      teamId: 'team-1',
      memberId: 'player-1',
      userId: 'player-1',
      fullName: 'Jugador de prueba',
      email: 'player@example.com',
      role: UserRole.player,
      active: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentMembershipProvider.overrideWithValue(user),
          teamRepositoryProvider.overrideWithValue(_FakeTeamRepository()),
          attendanceRepositoryProvider.overrideWithValue(
            _FakeAttendanceRepository(),
          ),
          teamProvider('team-1').overrideWith((ref) => Stream.value(null)),
          teamSessionsProvider(
            'team-1',
          ).overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Mantienes tus otros equipos'), findsOneWidget);
    expect(find.text('Salir de esta cuenta'), findsOneWidget);

    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Cerrarás la sesión en este dispositivo. Tu cuenta, equipo y datos '
        'no se modificarán.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('account-confirmation-dialog')))
          .width,
      lessThanOrEqualTo(460),
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salir de este equipo'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Dejarás de ver el calendario y las sesiones de este equipo. '
        'Mantendrás el acceso a tus otros equipos.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('account-confirmation-dialog')))
          .width,
      lessThanOrEqualTo(460),
    );
  });
}

class _FakeTeamRepository implements TeamRepository {
  @override
  Stream<List<TeamMembership>> watchTeamMembers(String teamId) =>
      Stream.value(const <TeamMembership>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAttendanceRepository implements AttendanceRepository {
  @override
  Stream<AttendanceHistorySnapshot> watchAttendanceForSessions(
    Iterable<String> sessionIds,
  ) {
    return Stream.value(
      const AttendanceHistorySnapshot(
        attendanceBySession: {},
        loadedSessionIds: {},
        totalSessionCount: 0,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
