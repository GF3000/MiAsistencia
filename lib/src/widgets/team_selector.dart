import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/app_user.dart';
import '../models/team_membership.dart';
import '../providers.dart';
import '../theme/app_theme.dart';

/// AppBar dropdown showing the active team name; opening it lists the user's
/// teams (to switch) plus "Crear equipo" and "Unirme con código".
class TeamDropdown extends ConsumerWidget {
  const TeamDropdown({
    required this.membership,
    required this.teamName,
    super.key,
  });

  final TeamRosterMember membership;
  final String teamName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membershipsAsync = ref.watch(
      membershipsForUserProvider(membership.id),
    );
    final memberships = membershipsAsync.value ?? const <TeamMembership>[];
    final activeTeams = memberships
        .where((member) => member.active)
        .toList();

    return PopupMenuButton<String>(
      key: const ValueKey('team-dropdown'),
      tooltip: 'Cambiar de equipo',
      onSelected: (value) async {
        if (value == 'create' || value == 'join') {
          context.push(
            '/onboarding?tab=${value == 'create' ? 0 : 1}',
          );
          return;
        }
        if (value == membership.teamId) {
          return;
        }
        await ref
            .read(teamRepositoryProvider)
            .setActiveTeam(userId: membership.id, teamId: value);
      },
      itemBuilder: (context) => [
        if (membershipsAsync.isLoading)
          const PopupMenuItem<String>(
            enabled: false,
            child: SizedBox(
              height: 32,
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (activeTeams.isEmpty)
          const PopupMenuItem<String>(
            enabled: false,
            child: Text('No perteneces a ningún equipo.'),
          )
        else ...[
          for (final member in activeTeams)
            PopupMenuItem<String>(
              value: member.teamId,
              child: _TeamDropdownItem(
                teamId: member.teamId,
                role: member.role,
                isActive: member.teamId == membership.teamId,
              ),
            ),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'create',
          child: ListTile(
            leading: Icon(Icons.add_business_outlined),
            title: Text('Crear equipo'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'join',
          child: ListTile(
            leading: Icon(Icons.group_add_outlined),
            title: Text('Unirme con código'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_2_outlined, size: 20, color: AppTheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                teamName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: AppTheme.navy),
          ],
        ),
      ),
    );
  }
}

class _TeamDropdownItem extends ConsumerWidget {
  const _TeamDropdownItem({
    required this.teamId,
    required this.role,
    required this.isActive,
  });

  final String teamId;
  final UserRole role;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamAsync = ref.watch(teamProvider(teamId));
    final name = teamAsync.value?.name ?? teamId;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isActive ? Icons.check_circle : Icons.sports_basketball_outlined,
          size: 20,
          color: isActive ? AppTheme.primary : Colors.blueGrey.shade400,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(name, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 12),
        Text(
          role.label,
          style: TextStyle(
            color: Colors.blueGrey.shade600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
