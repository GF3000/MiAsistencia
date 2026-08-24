import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/attendance.dart';
import 'package:mi_asistencia/src/widgets/attendance_editor.dart';

void main() {
  testWidgets('player attendance options are directly selectable', (
    tester,
  ) async {
    AttendanceStatus? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerAttendanceChoices(
            selectedStatus: AttendanceStatus.attending,
            onSelected: (status) => selected = status,
          ),
        ),
      ),
    );

    expect(find.text('Asisto'), findsOneWidget);
    expect(find.text('No asisto'), findsOneWidget);
    expect(find.text('Llego tarde'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-status-absent')));
    expect(selected, AttendanceStatus.absent);
  });

  testWidgets('selected attendance uses its status color without a checkmark', (
    tester,
  ) async {
    for (final status in AttendanceStatus.playerOptions) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerAttendanceChoices(
              selectedStatus: status,
              onSelected: (_) {},
            ),
          ),
        ),
      );

      final chipFinder = find.byKey(
        ValueKey('player-status-${status.firestoreValue}'),
      );
      final choiceChipFinder = find.descendant(
        of: chipFinder,
        matching: find.byType(ChoiceChip),
      );
      final chip = tester.widget<ChoiceChip>(choiceChipFinder);
      final icon = tester.widget<Icon>(
        find.descendant(of: chipFinder, matching: find.byIcon(status.icon)),
      );

      expect(chip.selected, isTrue);
      expect(chip.showCheckmark, isFalse);
      expect(chip.selectedColor, status.color);
      expect(chip.labelStyle?.color, Colors.white);
      expect(icon.color, Colors.white);
    }
  });

  testWidgets('changing attendance can collect an optional note', (
    tester,
  ) async {
    String? savedNote;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                savedNote = await showOptionalAttendanceNoteDialog(
                  context: context,
                  status: AttendanceStatus.late,
                  initialNote: 'Nota anterior',
                );
              },
              child: const Text('Cambiar'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Cambiar'));
    await tester.pumpAndSettle();
    expect(find.text('Llego tarde'), findsOneWidget);
    expect(find.text('Nota (opcional)'), findsOneWidget);
    expect(find.text('Nota anterior'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('quick-attendance-note')),
      'Llegaré 10 minutos tarde',
    );
    await tester.tap(find.text('Guardar nota'));
    await tester.pumpAndSettle();

    expect(savedNote, 'Llegaré 10 minutos tarde');
  });

  testWidgets('attendance note can be edited without changing status', (
    tester,
  ) async {
    String? savedNote;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerAttendanceNoteField(
            note: 'Nota original',
            onSave: (note) async => savedNote = note,
          ),
        ),
      ),
    );

    expect(find.text('Notas'), findsOneWidget);
    expect(find.text('Nota original'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('player-attendance-note')),
      'Nueva nota',
    );
    await tester.pump();
    final saveButton = find.byKey(
      const ValueKey('save-player-attendance-note'),
    );
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(savedNote, 'Nueva nota');
  });
}
