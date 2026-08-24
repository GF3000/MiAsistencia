import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/attendance.dart';
import 'package:mi_asistencia/src/repositories/attendance_repository.dart';

void main() {
  test(
    'batch attendance stores attending instead of deleting a missing record',
    () {
      expect(
        planAttendanceWrite(
          status: AttendanceStatus.attending,
          note: '',
          isBatch: true,
        ),
        AttendanceWriteKind.set,
      );
      expect(
        planAttendanceWrite(
          status: AttendanceStatus.attending,
          note: '',
          isBatch: false,
        ),
        AttendanceWriteKind.delete,
      );
      expect(
        planAttendanceWrite(
          status: AttendanceStatus.attending,
          note: '',
          isBatch: false,
          defaultStatus: AttendanceStatus.absent,
        ),
        AttendanceWriteKind.set,
      );
      expect(
        planAttendanceWrite(
          status: AttendanceStatus.absent,
          note: '',
          isBatch: false,
          defaultStatus: AttendanceStatus.absent,
        ),
        AttendanceWriteKind.delete,
      );
    },
  );
}
