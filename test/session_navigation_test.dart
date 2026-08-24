import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/team_session.dart';
import 'package:mi_asistencia/src/screens/session_detail_screen.dart';
import 'package:mi_asistencia/src/theme/app_theme.dart';

void main() {
  final sessions = [
    TeamSession(
      id: 'middle',
      teamId: 'team-1',
      title: 'Miércoles',
      startTime: DateTime(2026, 8, 26, 19),
      endTime: DateTime(2026, 8, 26, 20),
    ),
    TeamSession(
      id: 'first',
      teamId: 'team-1',
      title: 'Lunes',
      startTime: DateTime(2026, 8, 24, 19),
      endTime: DateTime(2026, 8, 24, 20),
    ),
    TeamSession(
      id: 'last',
      teamId: 'team-1',
      title: 'Viernes',
      startTime: DateTime(2026, 8, 28, 19),
      endTime: DateTime(2026, 8, 28, 20),
    ),
  ];

  test('finds previous and next sessions chronologically', () {
    final position = buildSessionTimelinePosition(
      sessions: sessions,
      currentSessionId: 'middle',
    );

    expect(position.previous?.id, 'first');
    expect(position.next?.id, 'last');
    expect(position.position, 2);
    expect(position.total, 3);
  });

  test('disables navigation at timeline edges', () {
    final first = buildSessionTimelinePosition(
      sessions: sessions,
      currentSessionId: 'first',
    );
    final last = buildSessionTimelinePosition(
      sessions: sessions,
      currentSessionId: 'last',
    );

    expect(first.previous, isNull);
    expect(first.next?.id, 'middle');
    expect(last.previous?.id, 'middle');
    expect(last.next, isNull);
  });

  testWidgets('renders adjacent session navigation on mobile', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var previousTapped = false;
    var nextTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: SessionTimelineNavigation(
              timeline: buildSessionTimelinePosition(
                sessions: sessions,
                currentSessionId: 'middle',
              ),
              onPrevious: () => previousTapped = true,
              onNext: () => nextTapped = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('2 de 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('previous-session')));
    await tester.tap(find.byKey(const ValueKey('next-session')));
    expect(previousTapped, isTrue);
    expect(nextTapped, isTrue);
  });
}
