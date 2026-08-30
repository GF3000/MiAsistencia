import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mi_asistencia/src/models/attendance.dart';
import 'package:mi_asistencia/src/models/player_motivation.dart';
import 'package:mi_asistencia/src/models/team_membership.dart';
import 'package:mi_asistencia/src/models/team_session.dart';
import 'package:mi_asistencia/src/widgets/player_attendance_profile_dialog.dart';

void main() {
  test('complete attendance counts as 100%', () {
    expect(participationForAttendanceChart(AttendanceStatus.attending), 1.0);
  });

  test('partial attendance counts as 50%', () {
    expect(participationForAttendanceChart(AttendanceStatus.gymOnly), 0.5);

    expect(participationForAttendanceChart(AttendanceStatus.courtOnly), 0.5);
  });

  test('absence and injury count as 0%', () {
    expect(participationForAttendanceChart(AttendanceStatus.absent), 0.0);

    expect(participationForAttendanceChart(AttendanceStatus.injured), 0.0);
  });
}
