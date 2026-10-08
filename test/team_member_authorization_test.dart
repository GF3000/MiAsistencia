import 'package:flutter_test/flutter_test.dart';
import 'package:mi_asistencia/src/models/app_user.dart';
import 'package:mi_asistencia/src/models/team_membership.dart';
import 'package:mi_asistencia/src/repositories/team_repository.dart';

void main() {
  TeamMembership membership({
    String teamId = 'team-a',
    UserRole role = UserRole.admin,
    bool active = true,
  }) {
    return TeamMembership(
      teamId: teamId,
      memberId: 'coach',
      userId: 'coach',
      fullName: 'Segundo Entrenador',
      email: 'coach@example.com',
      role: role,
      active: active,
    );
  }

  AppUser profile({String? teamId, UserRole role = UserRole.player}) {
    return AppUser(
      id: 'player',
      email: 'player@example.com',
      fullName: 'Marina García',
      role: role,
      teamId: teamId,
      active: true,
    );
  }

  group('ensureActiveCoachMembership', () {
    test('accepts an active coach membership of the team', () {
      expect(
        () => ensureActiveCoachMembership(
          membership(),
          'team-a',
          message: 'denied',
        ),
        returnsNormally,
      );
    });

    test('rejects a missing, inactive, player or other-team membership', () {
      final rejected = [
        null,
        membership(active: false),
        membership(role: UserRole.player),
        membership(teamId: 'team-b'),
      ];
      for (final actor in rejected) {
        expect(
          () => ensureActiveCoachMembership(actor, 'team-a', message: 'denied'),
          throwsA(
            isA<TeamException>().having((e) => e.message, 'message', 'denied'),
          ),
        );
      }
    });
  });

  group('shouldMirrorLegacyProfile', () {
    test('mirrors only a profile whose active team is this team', () {
      expect(shouldMirrorLegacyProfile(profile(teamId: 'team-a'), 'team-a'),
          isTrue);
    });

    test('skips a player whose active team is another team', () {
      expect(shouldMirrorLegacyProfile(profile(teamId: 'team-b'), 'team-a'),
          isFalse);
    });

    test('skips an unreadable or teamless profile', () {
      expect(shouldMirrorLegacyProfile(null, 'team-a'), isFalse);
      expect(shouldMirrorLegacyProfile(profile(), 'team-a'), isFalse);
    });
  });
}
