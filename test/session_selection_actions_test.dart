import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/screens/dashboard_screen.dart';
import 'package:mi_asistencia/src/theme/app_theme.dart';

void main() {
  testWidgets('player selection action remains fixed while content scrolls', (
    tester,
  ) async {
    var cleared = false;
    var attendanceOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListView(
            children: List.generate(
              30,
              (index) => SizedBox(height: 80, child: Text('Sesión $index')),
            ),
          ),
          bottomNavigationBar: SessionSelectionBottomBar(
            count: 3,
            isCoach: false,
            onClear: () => cleared = true,
            onEdit: () {},
            onDelete: () {},
            onAttendance: () => attendanceOpened = true,
          ),
        ),
      ),
    );

    final bar = find.byKey(const ValueKey('session-selection-bottom-bar'));
    final initialPosition = tester.getTopLeft(bar);
    expect(find.text('3 sesiones seleccionadas'), findsOneWidget);
    expect(find.text('Cambiar asistencia'), findsOneWidget);
    expect(find.text('Modificar'), findsNothing);
    expect(find.text('Eliminar'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(bar), initialPosition);

    await tester.tap(find.byKey(const ValueKey('batch-attendance-action')));
    expect(attendanceOpened, isTrue);
    await tester.tap(find.byKey(const ValueKey('clear-session-selection')));
    expect(cleared, isTrue);
  });

  testWidgets('coach selection bar separates edit and destructive actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: SessionSelectionBottomBar(
            count: 2,
            isCoach: true,
            onClear: _doNothing,
            onEdit: _doNothing,
            onDelete: _doNothing,
            onAttendance: _doNothing,
          ),
        ),
      ),
    );

    expect(find.text('2 sesiones seleccionadas'), findsOneWidget);
    expect(find.byKey(const ValueKey('batch-edit-action')), findsOneWidget);
    expect(find.byKey(const ValueKey('batch-delete-action')), findsOneWidget);
    expect(find.byKey(const ValueKey('batch-attendance-action')), findsNothing);
  });
}

void _doNothing() {}
