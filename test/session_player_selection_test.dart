import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/screens/session_detail_screen.dart';
import 'package:mi_asistencia/src/theme/app_theme.dart';

void main() {
  testWidgets('player selection bar stays fixed while the roster scrolls', (
    tester,
  ) async {
    var cancelled = false;
    var selectedAll = false;
    var applied = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListView(
            children: List.generate(
              30,
              (index) => SizedBox(height: 80, child: Text('Jugador $index')),
            ),
          ),
          bottomNavigationBar: SessionPlayerSelectionBar(
            count: 3,
            saving: false,
            onCancel: () => cancelled = true,
            onSelectAll: () => selectedAll = true,
            onApply: () => applied = true,
          ),
        ),
      ),
    );

    final bar = find.byKey(const ValueKey('player-selection-bottom-bar'));
    final initialPosition = tester.getTopLeft(bar);
    expect(find.text('3 jugadores seleccionados'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(bar), initialPosition);

    await tester.tap(find.byKey(const ValueKey('select-all-players')));
    await tester.tap(find.byKey(const ValueKey('apply-player-status')));
    await tester.tap(find.byKey(const ValueKey('clear-player-selection')));
    expect(selectedAll, isTrue);
    expect(applied, isTrue);
    expect(cancelled, isTrue);
  });

  testWidgets('actions are disabled while saving', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          bottomNavigationBar: SessionPlayerSelectionBar(
            count: 1,
            saving: true,
            onCancel: () {},
            onSelectAll: () {},
            onApply: () {},
          ),
        ),
      ),
    );

    expect(find.text('1 jugador seleccionado'), findsOneWidget);
    expect(find.text('Aplicando…'), findsOneWidget);
    final selectAll = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('select-all-players')),
    );
    expect(selectAll.onPressed, isNull);
  });

  group('CoachPlayerSelection', () {
    test('select all adds only the visible players and keeps others', () {
      final selection = CoachPlayerSelection()
        ..toggle('hidden')
        ..visibleIds = ['ana', 'bea'];
      selection.selectAllVisible();
      expect(selection.selectedIds, {'hidden', 'ana', 'bea'});
    });

    test('unselecting the last player leaves selection mode', () {
      final selection = CoachPlayerSelection()..toggle('ana');
      expect(selection.active, isTrue);
      selection.toggle('ana');
      expect(selection.active, isFalse);
    });
  });
}
