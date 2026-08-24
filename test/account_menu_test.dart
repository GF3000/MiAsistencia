import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/app.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/providers.dart';
import 'package:mi_asistencia/src/screens/dashboard_screen.dart';

void main() {
  testWidgets('account actions are distinct and require confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const user = AppUser(
      id: 'player-1',
      email: 'player@example.com',
      fullName: 'Jugador de prueba',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          teamProvider('team-1').overrideWith((ref) => Stream.value(null)),
          teamSessionsProvider(
            'team-1',
          ).overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MiAsistenciaApp(home: DashboardScreen(user: user)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Mantienes tu cuenta'), findsOneWidget);
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
    await tester.tap(find.text('Salir del equipo'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Dejarás de ver el calendario y las sesiones de este equipo. '
        'Tu cuenta seguirá activa y podrás unirte a otro equipo.',
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
