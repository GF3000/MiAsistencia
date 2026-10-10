import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/models/attendance.dart';

void main() {
  final sessionTime = DateTime(2026, 8, 24);

  AppUser player(
    String id, {
    AttendancePresumption presumption = AttendancePresumption.attending,
  }) {
    return AppUser(
      id: id,
      email: '$id@example.com',
      fullName: id,
      role: UserRole.player,
      teamId: 'team-1',
      active: true,
      attendancePresumption: presumption,
    );
  }

  AttendanceRecord record(String id, AttendanceStatus status) {
    return AttendanceRecord(userId: id, status: status);
  }

  test('splits attendance into presumed attending and presumed absent', () {
    const absent = AttendancePresumption.absent;
    final members = [
      player('a'),
      player('b'),
      player('c'),
      player('d'),
      player('x', presumption: absent),
      player('y', presumption: absent),
      player('z', presumption: absent),
    ];
    final attendance = {
      'c': record('c', AttendanceStatus.absent),
      'd': record('d', AttendanceStatus.noConvocado),
      'x': record('x', AttendanceStatus.attending),
      'y': record('y', AttendanceStatus.late),
    };

    final count = countAttendingPlayers(
      members: members,
      attendance: attendance,
      sessionTime: sessionTime,
    );

    expect(count.attending, 2);
    expect(count.expected, 3);
    expect(count.extra, 2);
    expect(count.label, '2/3 + 2');
  });

  test('omits the extra part when no presumed-absent player attends', () {
    final count = countAttendingPlayers(
      members: [
        player('a'),
        player('x', presumption: AttendancePresumption.absent),
      ],
      attendance: const {},
      sessionTime: sessionTime,
    );

    expect(count.label, '1/1');
  });

  test('coach summary applies the split to court and physical', () {
    final summary = buildCoachAttendanceSummary(
      members: [
        player('a'),
        player('b'),
        player('x', presumption: AttendancePresumption.absent),
      ],
      attendance: {
        'b': record('b', AttendanceStatus.gymOnly),
        'x': record('x', AttendanceStatus.courtOnly),
      },
      sessionTime: sessionTime,
    );

    expect(summary.court.label, '1/2 + 1');
    expect(summary.physical.label, '2/2');
  });
}
