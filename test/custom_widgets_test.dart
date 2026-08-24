import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/theme/app_theme.dart';
import 'package:mi_asistencia/src/widgets/app_notification.dart';
import 'package:mi_asistencia/src/widgets/session_view_switcher.dart';

void main() {
  testWidgets('session view switcher changes between list and calendar', (
    tester,
  ) async {
    var selectedView = SessionViewMode.list;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SessionViewSwitcher(
              value: selectedView,
              onChanged: (value) => setState(() => selectedView = value),
            ),
          ),
        ),
      ),
    );

    expect(selectedView, SessionViewMode.list);
    await tester.tap(find.byKey(const ValueKey('session-view-calendar')));
    await tester.pumpAndSettle();

    expect(selectedView, SessionViewMode.calendar);
    expect(find.byKey(const ValueKey('session-view-players')), findsNothing);
  });

  testWidgets('session view switcher offers players to coaches', (
    tester,
  ) async {
    var selectedView = SessionViewMode.list;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SessionViewSwitcher(
              value: selectedView,
              showPlayers: true,
              onChanged: (value) => setState(() => selectedView = value),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('session-view-players')));
    await tester.pumpAndSettle();

    expect(selectedView, SessionViewMode.players);
    expect(find.text('Jugadores'), findsOneWidget);
  });

  testWidgets('app notification shows its custom variant and can close', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppNotification(
                context,
                message: 'Cambios guardados.',
                type: AppNotificationType.success,
              ),
              child: const Text('Mostrar'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Mostrar'));
    await tester.pumpAndSettle();

    expect(find.byType(AppNotification), findsOneWidget);
    expect(find.text('Cambios guardados.'), findsOneWidget);
    expect(
      tester.widget<AppNotification>(find.byType(AppNotification)).type,
      AppNotificationType.success,
    );

    await tester.tap(find.byKey(const ValueKey('app-notification-close')));
    await tester.pumpAndSettle();

    expect(find.byType(AppNotification), findsNothing);
  });
}
