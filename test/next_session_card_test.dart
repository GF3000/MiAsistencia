import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/models/attendance.dart';
import 'package:mi_asistencia/src/models/team_session.dart';
import 'package:mi_asistencia/src/providers.dart';
import 'package:mi_asistencia/src/repositories/attendance_repository.dart';
import 'package:mi_asistencia/src/theme/app_theme.dart';
import 'package:mi_asistencia/src/widgets/next_session_card.dart';

void main() {
  testWidgets('highlighted session opens from its full non-control surface', (
    tester,
  ) async {
    var openCount = 0;
    final session = TeamSession(
      id: 'session-1',
      teamId: 'team-1',
      title: 'Entrenamiento del martes',
      startTime: DateTime(2026, 8, 25, 19),
      endTime: DateTime(2026, 8, 25, 20, 30),
    );
    const user = AppUser(
      id: 'player-1',
      email: 'player@example.com',
      fullName: 'Jugador',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attendanceRepositoryProvider.overrideWithValue(
            _FakeAttendanceRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: NextSessionCard(
              session: session,
              user: user,
              onOpen: () => openCount++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Entrenamiento del martes'));
    expect(openCount, 1);

    await tester.tap(find.byKey(const ValueKey('player-status-attending')));
    expect(openCount, 1);
  });

  testWidgets('missing attendance uses the player configured default', (
    tester,
  ) async {
    final session = TeamSession(
      id: 'session-1',
      teamId: 'team-1',
      title: 'Entrenamiento',
      startTime: DateTime(2026, 8, 25, 19),
      endTime: DateTime(2026, 8, 25, 20, 30),
    );
    const user = AppUser(
      id: 'player-1',
      email: 'player@example.com',
      fullName: 'Jugador',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
      attendancePresumption: AttendancePresumption.absent,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attendanceRepositoryProvider.overrideWithValue(
            _FakeAttendanceRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: NextSessionCard(session: session, user: user, onOpen: () {}),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No asisto'), findsOneWidget);
  });
}

class _FakeAttendanceRepository implements AttendanceRepository {
  @override
  Stream<AttendanceRecord?> watchAttendance({
    required String sessionId,
    required String userId,
  }) {
    return Stream.value(null);
  }

  @override
  Future<void> saveAttendance({
    required String sessionId,
    required String userId,
    required AttendanceStatus status,
    required String note,
    required String updatedBy,
    AttendanceStatus defaultStatus = AttendanceStatus.attending,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
