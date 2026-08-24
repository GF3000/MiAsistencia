import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/models/attendance.dart';
import 'package:mi_asistencia/src/models/team_membership.dart';

void main() {
  group('MembershipPeriod', () {
    test('isActiveAt uses [joinedAt, leftAt) semantics', () {
      final period = MembershipPeriod(
        joinedAt: DateTime(2026, 1, 10),
        leftAt: DateTime(2026, 3, 1),
      );

      expect(period.isActiveAt(DateTime(2026, 1, 9)), isFalse);
      expect(period.isActiveAt(DateTime(2026, 1, 10)), isTrue);
      expect(period.isActiveAt(DateTime(2026, 2, 15)), isTrue);
      expect(period.isActiveAt(DateTime(2026, 3, 1)), isFalse);
      expect(period.isActiveAt(DateTime(2026, 3, 2)), isFalse);
    });

    test('an open period (no leftAt) stays active indefinitely', () {
      final period = MembershipPeriod(joinedAt: DateTime(2026, 1, 10));

      expect(period.isOpen, isTrue);
      expect(period.isActiveAt(DateTime(2030, 1, 1)), isTrue);
    });

    test('round-trips through Firestore map serialization', () {
      final period = MembershipPeriod(
        joinedAt: DateTime(2026, 1, 10),
        leftAt: DateTime(2026, 3, 1),
      );

      final map = period.toMap();
      expect(map['joinedAt'], Timestamp.fromDate(period.joinedAt));
      expect(map['leftAt'], Timestamp.fromDate(period.leftAt!));

      final parsed = MembershipPeriod.fromFirestore(map);
      expect(parsed.joinedAt, period.joinedAt);
      expect(parsed.leftAt, period.leftAt);
    });

    test('serializes an open period with a null leftAt', () {
      final period = MembershipPeriod(joinedAt: DateTime(2026, 1, 10));

      final map = period.toMap();
      expect(map['leftAt'], isNull);

      final parsed = MembershipPeriod.fromFirestore(map);
      expect(parsed.leftAt, isNull);
      expect(parsed.isOpen, isTrue);
    });

    test('rejects a period without a joinedAt timestamp', () {
      expect(
        () => MembershipPeriod.fromFirestore(const {}),
        throwsFormatException,
      );
    });
  });

  group('TeamMembership', () {
    TeamMembership membershipWithPeriods(List<MembershipPeriod> periods) {
      return TeamMembership(
        teamId: 'team-1',
        memberId: 'member-1',
        userId: 'user-1',
        fullName: 'Marina García',
        email: 'marina@example.com',
        role: UserRole.player,
        active: true,
        membershipPeriods: periods,
      );
    }

    test('isActiveAt consults every period, not only the active flag', () {
      final membership = membershipWithPeriods([
        MembershipPeriod(
          joinedAt: DateTime(2026, 1, 1),
          leftAt: DateTime(2026, 2, 1),
        ),
        MembershipPeriod(joinedAt: DateTime(2026, 4, 1)),
      ]);

      // Gap between leave and rejoin: not active even though `active` (the
      // flat flag) may still say true.
      expect(membership.isActiveAt(DateTime(2026, 3, 1)), isFalse);
      // Active during the first stint.
      expect(membership.isActiveAt(DateTime(2026, 1, 15)), isTrue);
      // Active again after rejoining, and still active far in the future
      // because the second period is open.
      expect(membership.isActiveAt(DateTime(2026, 4, 15)), isTrue);
      expect(membership.isActiveAt(DateTime(2030, 1, 1)), isTrue);
      // Before ever joining.
      expect(membership.isActiveAt(DateTime(2025, 12, 31)), isFalse);
    });

    test(
      'inactive flag with legacy empty periods still respects createdAt',
      () {
        final membership = TeamMembership(
          teamId: 'team-1',
          memberId: 'member-1',
          fullName: 'Marina García',
          email: 'marina@example.com',
          role: UserRole.player,
          active: false,
          createdAt: DateTime(2026, 1, 1),
        );

        expect(membership.isActiveAt(DateTime(2026, 6, 1)), isFalse);
      },
    );

    test('active flag with legacy empty periods and no createdAt is treated '
        'as active since inception (defensive default)', () {
      final membership = TeamMembership(
        teamId: 'team-1',
        memberId: 'member-1',
        fullName: 'Marina García',
        email: 'marina@example.com',
        role: UserRole.player,
        active: true,
      );

      expect(membership.isActiveAt(DateTime(2000, 1, 1)), isTrue);
      expect(membership.teamMembershipStartedAt, isNull);
    });

    test('active flag with legacy empty periods honors createdAt as the start '
        'boundary', () {
      final membership = TeamMembership(
        teamId: 'team-1',
        memberId: 'member-1',
        fullName: 'Marina García',
        email: 'marina@example.com',
        role: UserRole.player,
        active: true,
        createdAt: DateTime(2026, 5, 1),
      );

      expect(membership.isActiveAt(DateTime(2026, 4, 1)), isFalse);
      expect(membership.isActiveAt(DateTime(2026, 5, 1)), isTrue);
      expect(membership.teamMembershipStartedAt, DateTime(2026, 5, 1));
    });

    test('openPeriod and currentPeriod reflect the roster history', () {
      final closed = MembershipPeriod(
        joinedAt: DateTime(2026, 1, 1),
        leftAt: DateTime(2026, 2, 1),
      );
      final open = MembershipPeriod(joinedAt: DateTime(2026, 4, 1));
      final membership = membershipWithPeriods([closed, open]);

      expect(membership.openPeriod, same(open));
      expect(membership.currentPeriod, same(open));
      expect(membershipWithPeriods([closed]).openPeriod, isNull);
      expect(membershipWithPeriods([closed]).currentPeriod, same(closed));
      expect(membershipWithPeriods(const []).currentPeriod, isNull);
    });

    test('teamMembershipStartedAt is the earliest joinedAt across periods', () {
      final membership = membershipWithPeriods([
        MembershipPeriod(
          joinedAt: DateTime(2026, 4, 1),
          leftAt: DateTime(2026, 5, 1),
        ),
        MembershipPeriod(joinedAt: DateTime(2026, 1, 1)),
      ]);

      expect(membership.teamMembershipStartedAt, DateTime(2026, 1, 1));
    });

    test('a managed player keeps a stable memberId as the attendance document '
        'id and reports having no linked account', () {
      const managedMembership = TeamMembership(
        teamId: 'team-1',
        memberId: 'managed-player-1',
        fullName: 'Jugador gestionado',
        email: '',
        role: UserRole.player,
        active: true,
        managedByCoach: true,
      );

      expect(managedMembership.userId, isNull);
      expect(managedMembership.hasAccount, isFalse);
      expect(managedMembership.id, 'managed-player-1');

      const accountMembership = TeamMembership(
        teamId: 'team-1',
        memberId: 'user-42',
        userId: 'user-42',
        fullName: 'Marina García',
        email: 'marina@example.com',
        role: UserRole.player,
        active: true,
      );
      expect(accountMembership.hasAccount, isTrue);
      expect(accountMembership.id, accountMembership.userId);
    });

    test('isCoach mirrors the role', () {
      final membership = membershipWithPeriods(const []);
      expect(membership.isCoach, isFalse);

      final coachMembership = TeamMembership(
        teamId: 'team-1',
        memberId: 'coach-1',
        userId: 'coach-1',
        fullName: 'Entrenador',
        email: 'coach@example.com',
        role: UserRole.admin,
        active: true,
      );
      expect(coachMembership.isCoach, isTrue);
    });

    test('attendancePresumptionAt resolves the latest applicable change', () {
      final membership = TeamMembership(
        teamId: 'team-1',
        memberId: 'member-1',
        fullName: 'Marina García',
        email: 'marina@example.com',
        role: UserRole.player,
        active: true,
        attendancePresumptionHistory: [
          AttendancePresumptionChange(
            value: AttendancePresumption.absent,
            effectiveFrom: DateTime(2026, 2, 1),
          ),
          AttendancePresumptionChange(
            value: AttendancePresumption.attending,
            effectiveFrom: DateTime(2026, 3, 1),
          ),
        ],
      );

      expect(
        membership.attendancePresumptionAt(DateTime(2026, 1, 15)),
        AttendancePresumption.attending,
      );
      expect(
        membership.attendancePresumptionAt(DateTime(2026, 2, 15)),
        AttendancePresumption.absent,
      );
      expect(
        membership.attendancePresumptionAt(DateTime(2026, 3, 15)),
        AttendancePresumption.attending,
      );
    });

    test(
      'attendance presumption starts as attending before the first change',
      () {
        final membership = TeamMembership(
          teamId: 'team-1',
          memberId: 'member-1',
          fullName: 'Marina García',
          email: 'marina@example.com',
          role: UserRole.player,
          active: true,
          attendancePresumption: AttendancePresumption.absent,
          attendancePresumptionHistory: [
            AttendancePresumptionChange(
              value: AttendancePresumption.absent,
              effectiveFrom: DateTime(2026, 2, 1),
            ),
          ],
        );

        expect(
          membership.attendancePresumptionAt(DateTime(2026, 1, 15)),
          AttendancePresumption.attending,
        );
        expect(
          membership.attendancePresumptionAt(DateTime(2026, 2, 15)),
          AttendancePresumption.absent,
        );
      },
    );

    test('round-trips through Firestore map serialization', () {
      final membership = TeamMembership(
        teamId: 'team-1',
        memberId: 'member-1',
        userId: 'user-1',
        fullName: 'Marina García',
        email: 'marina@example.com',
        role: UserRole.admin,
        active: true,
        managedByCoach: false,
        membershipPeriods: [
          MembershipPeriod(
            joinedAt: DateTime(2026, 1, 1),
            leftAt: DateTime(2026, 2, 1),
          ),
          MembershipPeriod(joinedAt: DateTime(2026, 4, 1)),
        ],
        attendancePresumption: AttendancePresumption.absent,
        attendancePresumptionHistory: [
          AttendancePresumptionChange(
            value: AttendancePresumption.attending,
            effectiveFrom: DateTime(2026, 3, 1),
          ),
        ],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 4, 1),
        migrationVersion: 1,
      );

      final map = membership.toMap();
      final parsed = TeamMembership.fromFirestore(
        map,
        documentId: 'fallback-id',
      );

      expect(parsed.teamId, membership.teamId);
      expect(parsed.memberId, membership.memberId);
      expect(parsed.userId, membership.userId);
      expect(parsed.fullName, membership.fullName);
      expect(parsed.email, membership.email);
      expect(parsed.role, membership.role);
      expect(parsed.active, membership.active);
      expect(parsed.managedByCoach, membership.managedByCoach);
      expect(parsed.membershipPeriods.length, 2);
      expect(
        parsed.membershipPeriods[0].joinedAt,
        membership.membershipPeriods[0].joinedAt,
      );
      expect(
        parsed.membershipPeriods[0].leftAt,
        membership.membershipPeriods[0].leftAt,
      );
      expect(parsed.membershipPeriods[1].isOpen, isTrue);
      expect(parsed.attendancePresumption, membership.attendancePresumption);
      expect(parsed.attendancePresumptionHistory.length, 1);
      expect(
        parsed.attendancePresumptionHistory.first.value,
        AttendancePresumption.attending,
      );
      expect(parsed.createdAt, membership.createdAt);
      expect(parsed.updatedAt, membership.updatedAt);
      expect(parsed.migrationVersion, membership.migrationVersion);
    });

    test(
      'fromFirestore falls back to the document id when memberId is absent',
      () {
        final parsed = TeamMembership.fromFirestore(const <String, dynamic>{
          'teamId': 'team-1',
          'role': 'player',
        }, documentId: 'doc-id-1');

        expect(parsed.memberId, 'doc-id-1');
        expect(parsed.id, 'doc-id-1');
        expect(parsed.userId, isNull);
        expect(parsed.hasAccount, isFalse);
        expect(parsed.active, isTrue);
      },
    );
  });

  group('legacy AppUser compatibility', () {
    test('AppUser satisfies the TeamRosterMember contract unchanged', () {
      const player = AppUser(
        id: 'player-1',
        email: 'player@example.com',
        fullName: 'Marina García',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
        teamJoinedAt: null,
      );

      // ignore: unnecessary_type_check
      expect(player is TeamRosterMember, isTrue);
      expect(player.teamMembershipStartedAt, isNull);
      expect(
        player.attendancePresumptionAt(DateTime(2026, 1, 1)),
        AttendancePresumption.attending,
      );
    });

    test('resolveAttendanceStatus still treats sessions before a legacy join '
        'date as not applicable', () {
      final joinedPlayer = AppUser(
        id: 'player-1',
        email: 'player@example.com',
        fullName: 'Marina García',
        role: UserRole.player,
        teamId: 'team-1',
        active: true,
        teamJoinedAt: DateTime(2026, 8, 10),
      );

      expect(
        resolveAttendanceStatus(
          user: joinedPlayer,
          explicitRecord: null,
          sessionTime: DateTime(2026, 8, 9, 19),
        ),
        AttendanceStatus.notApplicable,
      );
      expect(
        resolveAttendanceStatus(
          user: joinedPlayer,
          explicitRecord: null,
          sessionTime: DateTime(2026, 8, 10, 19),
        ),
        AttendanceStatus.attending,
      );
    });

    test(
      'resolveAttendanceStatus works interchangeably with a TeamMembership',
      () {
        final membership = TeamMembership(
          teamId: 'team-1',
          memberId: 'member-1',
          userId: 'member-1',
          fullName: 'Marina García',
          email: 'marina@example.com',
          role: UserRole.player,
          active: true,
          membershipPeriods: [
            MembershipPeriod(joinedAt: DateTime(2026, 8, 10)),
          ],
        );

        expect(
          resolveAttendanceStatus(
            user: membership,
            explicitRecord: null,
            sessionTime: DateTime(2026, 8, 9, 19),
          ),
          AttendanceStatus.notApplicable,
        );
        expect(
          resolveAttendanceStatus(
            user: membership,
            explicitRecord: null,
            sessionTime: DateTime(2026, 8, 10, 19),
          ),
          AttendanceStatus.attending,
        );
      },
    );

    test(
      'resolveAttendanceStatus excludes membership gaps and closed periods',
      () {
        final membership = TeamMembership(
          teamId: 'team-1',
          memberId: 'member-1',
          userId: 'member-1',
          fullName: 'Marina García',
          email: 'marina@example.com',
          role: UserRole.player,
          active: false,
          membershipPeriods: [
            MembershipPeriod(
              joinedAt: DateTime(2026, 1, 1),
              leftAt: DateTime(2026, 2, 1),
            ),
            MembershipPeriod(
              joinedAt: DateTime(2026, 4, 1),
              leftAt: DateTime(2026, 5, 1),
            ),
          ],
        );

        expect(
          resolveAttendanceStatus(
            user: membership,
            explicitRecord: null,
            sessionTime: DateTime(2026, 3, 1),
          ),
          AttendanceStatus.notApplicable,
        );
        expect(
          resolveAttendanceStatus(
            user: membership,
            explicitRecord: null,
            sessionTime: DateTime(2026, 6, 1),
          ),
          AttendanceStatus.notApplicable,
        );
      },
    );
  });
}
