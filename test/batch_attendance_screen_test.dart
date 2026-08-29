import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/models/team_membership.dart';
import 'package:mi_asistencia/src/models/team_session.dart';
import 'package:mi_asistencia/src/providers.dart';
import 'package:mi_asistencia/src/screens/batch_attendance_screen.dart';

void main() {
  testWidgets('batch action stays fixed with one hundred sessions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const user = TeamMembership(
      teamId: 'team-1',
      memberId: 'player',
      userId: 'player',
      fullName: 'Jugador',
      email: 'player@example.com',
      role: UserRole.player,
      active: true,
    );
    final now = DateTime.now();
    final sessions = List.generate(100, (index) {
      final start = now.add(Duration(days: index + 1));
      return TeamSession(
        id: 'session-$index',
        teamId: 'team-1',
        title: 'Entrenamiento ${index + 1}',
        startTime: start,
        endTime: start.add(const Duration(hours: 1)),
      );
    });

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

    final bar = find.byKey(const ValueKey('batch-attendance-bottom-bar'));
    final initialPosition = tester.getTopLeft(bar);
    expect(find.text('100 sesiones seleccionadas'), findsOneWidget);
    expect(find.text('Cambiar asistencia'), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(bar), initialPosition);

    await tester.tap(find.byKey(const ValueKey('change-batch-attendance')));
    await tester.pumpAndSettle();
    expect(find.text('Estado y nota'), findsOneWidget);
    expect(find.text('El cambio se aplicará a 100 sesiones.'), findsOneWidget);
  });
}
