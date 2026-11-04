import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/models/attendance.dart';
import 'package:mi_asistencia/src/theme/app_theme.dart';
import 'package:mi_asistencia/src/utils/attendance_image.dart';
import 'package:mi_asistencia/src/widgets/player_attendance_table.dart';

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

const _stats = PlayerAttendanceStats(
  userId: 'ana',
  sessionCount: 10,
  eligibleSessionCount: 10,
  attendedSessionCount: 8,
  attendanceCount: 6,
  lateCount: 1,
  physicalCount: 7,
  courtCount: 8,
  absenceCount: 2,
  injuryCount: 0,
  matchCount: 3,
  uncalledMatchCount: 1,
);

void main() {
  testWidgets('renders the shareable table as a PNG', (tester) async {
    final bytes = await tester.runAsync(
      () => buildPlayerAttendanceImage(
        title: 'Juvenil Masculino',
        subtitle: '10 entrenamientos · 4 partidos',
        rows: [(playerName: 'Ana', stats: _stats)],
      ),
    );

    expect(bytes, isNotNull);
    expect(bytes!.take(8), _pngSignature);
  });

  testWidgets('downloads the table image from the export menu', (tester) async {
    String? downloadedName;
    Uint8List? downloadedBytes;
    String? downloadedType;
    const ana = AppUser(
      id: 'ana',
      email: 'ana@example.com',
      fullName: 'Ana',
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PlayerAttendanceTable(
            rows: const [PlayerAttendanceTableRow(player: ana, stats: _stats)],
            teamName: 'Juvenil Masculino',
            downloadImage:
                ({required fileName, required bytes, required mimeType}) {
                  downloadedName = fileName;
                  downloadedBytes = bytes;
                  downloadedType = mimeType;
                },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('attendance-csv-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descargar imagen'));
    // The menu reports the selection once its close animation finishes.
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      // Let the image render and encode outside the fake clock.
      for (
        var attempt = 0;
        attempt < 50 && downloadedBytes == null;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();

    expect(downloadedName, startsWith('estadisticas-jugadores-'));
    expect(downloadedName, endsWith('.png'));
    expect(downloadedType, 'image/png');
    expect(downloadedBytes!.take(8), _pngSignature);
  });
}
