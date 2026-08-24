import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../models/app_user.dart';
import '../providers.dart';
import '../repositories/team_repository.dart';
import '../theme/app_theme.dart';
import '../utils/team_invitation.dart';
import '../widgets/app_notification.dart';
import '../widgets/app_widgets.dart';

enum TeamMemberAction {
  makeCoach,
  makePlayer,
  presumeAttending,
  presumeAbsent,
  remove,
}

List<TeamMemberAction> availableTeamMemberActions({
  required AppUser currentUser,
  required AppUser member,
  required Team team,
}) {
  if (!currentUser.isCoach ||
      currentUser.id == member.id ||
      team.createdBy == member.id) {
    return const [];
  }
  if (member.isCoach) {
    return const [TeamMemberAction.makePlayer, TeamMemberAction.remove];
  }
  return [
    if (!member.managedByCoach) TeamMemberAction.makeCoach,
    member.attendancePresumption == AttendancePresumption.attending
        ? TeamMemberAction.presumeAbsent
        : TeamMemberAction.presumeAttending,
    TeamMemberAction.remove,
  ];
}

class ManageTeamScreen extends ConsumerStatefulWidget {
  const ManageTeamScreen({required this.currentUser, super.key});

  final AppUser currentUser;

  @override
  ConsumerState<ManageTeamScreen> createState() => _ManageTeamScreenState();
}

class _ManageTeamScreenState extends ConsumerState<ManageTeamScreen> {
  String? _busyMemberId;
  bool _addingPlayer = false;

  @override
  Widget build(BuildContext context) {
    final teamId = widget.currentUser.teamId!;
    final repository = ref.watch(teamRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Administrar equipo')),
      body: AppPageBody(
        child: StreamBuilder<Team?>(
          stream: repository.watchTeam(teamId),
          builder: (context, teamSnapshot) {
            if (teamSnapshot.hasError) {
              return const EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'No se pudo cargar el equipo',
                message: 'Comprueba tu conexión e inténtalo de nuevo.',
              );
            }
            if (teamSnapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final team = teamSnapshot.data;
            if (team == null) {
              return const EmptyState(
                icon: Icons.group_off_outlined,
                title: 'Equipo no disponible',
                message: 'Este equipo ya no existe.',
              );
            }
            return StreamBuilder<List<AppUser>>(
              stream: repository.watchMembers(teamId),
              builder: (context, membersSnapshot) {
                if (membersSnapshot.hasError) {
                  return const EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'No se pudo cargar la plantilla',
                    message: 'Comprueba tu conexión e inténtalo de nuevo.',
                  );
                }
                if (!membersSnapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final members = membersSnapshot.data!;
                final coaches = members
                    .where((member) => member.isCoach)
                    .toList();
                final players = members
                    .where((member) => !member.isCoach)
                    .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TeamManagementHeader(
                      team: team,
                      coachCount: coaches.length,
                      playerCount: players.length,
                      onShowInvitation: () => _showTeamInvitation(team),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        key: const ValueKey('add-managed-player'),
                        onPressed: _addingPlayer ? null : _addManagedPlayer,
                        icon: _addingPlayer
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Añadir jugador sin cuenta'),
                      ),
                    ),
                    const SizedBox(height: 26),
                    _MemberSection(
                      title: 'Entrenadores',
                      count: coaches.length,
                      members: coaches,
                      currentUser: widget.currentUser,
                      team: team,
                      busyMemberId: _busyMemberId,
                      onAction: _handleAction,
                    ),
                    const SizedBox(height: 26),
                    _MemberSection(
                      title: 'Jugadores',
                      count: players.length,
                      members: players,
                      currentUser: widget.currentUser,
                      team: team,
                      busyMemberId: _busyMemberId,
                      onAction: _handleAction,
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _showTeamInvitation(Team team) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.group_add_outlined,
                  color: AppTheme.primary,
                  size: 38,
                ),
                const SizedBox(height: 14),
                Text(
                  team.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Comparte este código con tus jugadores:',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SelectableText(
                  team.joinCode,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 7,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'También puedes copiar un enlace para que se unan '
                  'directamente.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cerrar'),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('copy-team-invite-link'),
                      onPressed: () => _copyTeamInviteLink(team),
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('Copiar enlace'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyTeamInviteLink(Team team) async {
    try {
      await ref.read(teamRepositoryProvider).ensurePublicTeamInvitation(team);
      await Clipboard.setData(
        ClipboardData(text: buildTeamInviteUrl(team.joinCode)),
      );
      if (mounted) {
        showAppNotification(
          context,
          message: 'Enlace de invitación copiado.',
          type: AppNotificationType.success,
        );
      }
    } on FirebaseException {
      if (mounted) {
        showAppNotification(
          context,
          message:
              'No se pudo preparar el enlace de invitación. Inténtalo de nuevo.',
          type: AppNotificationType.error,
        );
      }
    } on PlatformException {
      if (mounted) {
        showAppNotification(
          context,
          message: 'No se pudo copiar el enlace. Inténtalo de nuevo.',
          type: AppNotificationType.error,
        );
      }
    }
  }

  Future<void> _addManagedPlayer() async {
    final fullName = await showManagedPlayerNameDialog(context);
    if (fullName == null || !mounted) {
      return;
    }

    setState(() => _addingPlayer = true);
    try {
      await ref
          .read(teamRepositoryProvider)
          .createManagedPlayer(
            teamId: widget.currentUser.teamId!,
            actingUserId: widget.currentUser.id,
            fullName: fullName,
          );
      if (mounted) {
        showAppNotification(
          context,
          message: '$fullName se ha añadido al equipo.',
          type: AppNotificationType.success,
        );
      }
    } on TeamException catch (error) {
      if (mounted) {
        showAppNotification(
          context,
          message: error.message,
          type: AppNotificationType.error,
        );
      }
    } on FirebaseException {
      if (mounted) {
        showAppNotification(
          context,
          message: 'No se pudo añadir el jugador.',
          type: AppNotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _addingPlayer = false);
      }
    }
  }

  Future<void> _handleAction(AppUser member, TeamMemberAction action) async {
    final confirmed = await _confirmAction(member, action);
    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _busyMemberId = member.id);
    try {
      final repository = ref.read(teamRepositoryProvider);
      switch (action) {
        case TeamMemberAction.makeCoach:
          await repository.updateMemberRole(
            teamId: widget.currentUser.teamId!,
            memberId: member.id,
            actingUserId: widget.currentUser.id,
            role: UserRole.admin,
          );
          break;
        case TeamMemberAction.makePlayer:
          await repository.updateMemberRole(
            teamId: widget.currentUser.teamId!,
            memberId: member.id,
            actingUserId: widget.currentUser.id,
            role: UserRole.player,
          );
          break;
        case TeamMemberAction.presumeAttending:
          await repository.updateAttendancePresumption(
            teamId: widget.currentUser.teamId!,
            memberId: member.id,
            actingUserId: widget.currentUser.id,
            value: AttendancePresumption.attending,
          );
          break;
        case TeamMemberAction.presumeAbsent:
          await repository.updateAttendancePresumption(
            teamId: widget.currentUser.teamId!,
            memberId: member.id,
            actingUserId: widget.currentUser.id,
            value: AttendancePresumption.absent,
          );
          break;
        case TeamMemberAction.remove:
          await repository.removeMember(
            teamId: widget.currentUser.teamId!,
            memberId: member.id,
            actingUserId: widget.currentUser.id,
          );
          break;
      }
      if (mounted) {
        showAppNotification(
          context,
          message: switch (action) {
            TeamMemberAction.makeCoach =>
              '${member.fullName} ahora es entrenador.',
            TeamMemberAction.makePlayer =>
              '${member.fullName} ahora es jugador.',
            TeamMemberAction.presumeAttending =>
              '${member.fullName} tendrá presunción de asistencia.',
            TeamMemberAction.presumeAbsent =>
              '${member.fullName} tendrá presunción de no asistencia.',
            TeamMemberAction.remove =>
              '${member.fullName} ya no pertenece al equipo.',
          },
          type: AppNotificationType.success,
        );
      }
    } on TeamException catch (error) {
      if (mounted) {
        showAppNotification(
          context,
          message: error.message,
          type: AppNotificationType.error,
        );
      }
    } on FirebaseException {
      if (mounted) {
        showAppNotification(
          context,
          message: 'No se pudo actualizar el miembro.',
          type: AppNotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyMemberId = null);
      }
    }
  }

  Future<bool> _confirmAction(AppUser member, TeamMemberAction action) async {
    final title = switch (action) {
      TeamMemberAction.makeCoach => 'Hacer entrenador',
      TeamMemberAction.makePlayer => 'Hacer jugador',
      TeamMemberAction.presumeAttending => 'Presumir asistencia',
      TeamMemberAction.presumeAbsent => 'Presumir no asistencia',
      TeamMemberAction.remove => 'Expulsar del equipo',
    };
    final message = switch (action) {
      TeamMemberAction.makeCoach =>
        '${member.fullName} podrá crear sesiones, modificar asistencias y '
            'administrar miembros.',
      TeamMemberAction.makePlayer =>
        '${member.fullName} dejará de tener permisos para administrar el '
            'equipo.',
      TeamMemberAction.presumeAttending =>
        'En las sesiones futuras sin un estado específico, '
            '${member.fullName} aparecerá como asistente.',
      TeamMemberAction.presumeAbsent =>
        'En las sesiones futuras sin un estado específico, '
            '${member.fullName} aparecerá como no asistente.',
      TeamMemberAction.remove =>
        member.managedByCoach
            ? '${member.fullName} se eliminará de la plantilla.'
            : '${member.fullName} perderá el acceso al equipo, pero conservará '
                  'su cuenta.',
    };
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: Icon(
              action == TeamMemberAction.remove
                  ? Icons.person_remove_outlined
                  : action == TeamMemberAction.presumeAttending ||
                        action == TeamMemberAction.presumeAbsent
                  ? Icons.event_available_outlined
                  : Icons.manage_accounts_outlined,
            ),
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: action == TeamMemberAction.remove
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      )
                    : null,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(
                  action == TeamMemberAction.remove ? 'Expulsar' : 'Confirmar',
                ),
              ),
            ],
          ),
        ) ??
        false;
  }
}

Future<String?> showManagedPlayerNameDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => const _ManagedPlayerNameDialog(),
  );
}

class _ManagedPlayerNameDialog extends StatefulWidget {
  const _ManagedPlayerNameDialog();

  @override
  State<_ManagedPlayerNameDialog> createState() =>
      _ManagedPlayerNameDialogState();
}

class _ManagedPlayerNameDialogState extends State<_ManagedPlayerNameDialog> {
  final _nameController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final fullName = _nameController.text.trim();
    if (fullName.length < 2) {
      setState(() => _errorText = 'Escribe el nombre del jugador.');
      return;
    }
    Navigator.of(context).pop(fullName);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.person_add_alt_1_outlined),
      title: const Text('Añadir jugador sin cuenta'),
      content: TextField(
        key: const ValueKey('managed-player-name'),
        controller: _nameController,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.name],
        decoration: InputDecoration(
          labelText: 'Nombre completo',
          prefixIcon: const Icon(Icons.person_outline),
          helperText: 'El entrenador gestionará su asistencia.',
          errorText: _errorText,
        ),
        onChanged: (_) {
          if (_errorText != null) {
            setState(() => _errorText = null);
          }
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('confirm-add-managed-player'),
          onPressed: _submit,
          child: const Text('Añadir'),
        ),
      ],
    );
  }
}

class TeamManagementHeader extends StatelessWidget {
  const TeamManagementHeader({
    required this.team,
    required this.coachCount,
    required this.playerCount,
    required this.onShowInvitation,
    super.key,
  });

  final Team team;
  final int coachCount;
  final int playerCount;
  final VoidCallback onShowInvitation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.navy, AppTheme.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.groups_2_outlined, color: Colors.white, size: 34),
          const SizedBox(height: 14),
          Text(
            team.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$coachCount entrenadores · $playerCount jugadores',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Código ${team.joinCode}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  key: const ValueKey('show-team-invitation'),
                  tooltip: 'Ver y compartir código',
                  visualDensity: VisualDensity.compact,
                  color: Colors.white,
                  onPressed: onShowInvitation,
                  icon: const Icon(Icons.share_outlined, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberSection extends StatelessWidget {
  const _MemberSection({
    required this.title,
    required this.count,
    required this.members,
    required this.currentUser,
    required this.team,
    required this.busyMemberId,
    required this.onAction,
  });

  final String title;
  final int count;
  final List<AppUser> members;
  final AppUser currentUser;
  final Team team;
  final String? busyMemberId;
  final void Function(AppUser member, TeamMemberAction action) onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$title ($count)', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (members.isEmpty)
          Text(
            title == 'Jugadores'
                ? 'Todavía no hay jugadores en el equipo.'
                : 'No hay entrenadores disponibles.',
            style: TextStyle(color: Colors.blueGrey.shade600),
          )
        else
          ...members.map(
            (member) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TeamMemberCard(
                member: member,
                currentUser: currentUser,
                team: team,
                busy: busyMemberId == member.id,
                onAction: (action) => onAction(member, action),
              ),
            ),
          ),
      ],
    );
  }
}

class TeamMemberCard extends StatelessWidget {
  const TeamMemberCard({
    required this.member,
    required this.currentUser,
    required this.team,
    required this.busy,
    required this.onAction,
    super.key,
  });

  final AppUser member;
  final AppUser currentUser;
  final Team team;
  final bool busy;
  final ValueChanged<TeamMemberAction> onAction;

  @override
  Widget build(BuildContext context) {
    final actions = availableTeamMemberActions(
      currentUser: currentUser,
      member: member,
      team: team,
    );
    final isOwner = team.createdBy == member.id;
    final isCurrentUser = currentUser.id == member.id;
    final initials = member.fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: member.isCoach
                  ? AppTheme.primary.withValues(alpha: 0.12)
                  : const Color(0xFFEAF0F2),
              foregroundColor: member.isCoach
                  ? AppTheme.primary
                  : AppTheme.navy,
              child: Text(
                initials,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.fullName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    member.hasAccount ? member.email : 'Sin cuenta',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.blueGrey.shade600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _MemberTag(
                        label: member.role.label,
                        icon: member.isCoach
                            ? Icons.sports_outlined
                            : Icons.person_outline,
                        highlighted: member.isCoach,
                      ),
                      if (!member.isCoach)
                        _MemberTag(
                          label:
                              'Por defecto: '
                              '${member.attendancePresumption.label}',
                          icon:
                              member.attendancePresumption ==
                                  AttendancePresumption.attending
                              ? Icons.event_available_outlined
                              : Icons.event_busy_outlined,
                          highlighted:
                              member.attendancePresumption ==
                              AttendancePresumption.attending,
                        ),
                      if (member.managedByCoach)
                        const _MemberTag(
                          label: 'Gestionado por entrenador',
                          icon: Icons.sports_outlined,
                          highlighted: false,
                        ),
                      if (isOwner)
                        const _MemberTag(
                          label: 'Propietario',
                          icon: Icons.workspace_premium_outlined,
                          highlighted: true,
                        ),
                      if (isCurrentUser)
                        const _MemberTag(
                          label: 'Tú',
                          icon: Icons.check,
                          highlighted: false,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (actions.isNotEmpty)
              PopupMenuButton<TeamMemberAction>(
                key: ValueKey('member-actions-${member.id}'),
                tooltip: 'Administrar a ${member.fullName}',
                constraints: const BoxConstraints(minWidth: 260, maxWidth: 320),
                onSelected: onAction,
                itemBuilder: (context) => actions
                    .map(
                      (action) => PopupMenuItem(
                        value: action,
                        child: Row(
                          children: [
                            Icon(
                              action.icon,
                              color: action == TeamMemberAction.remove
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                action.label,
                                overflow: TextOverflow.ellipsis,
                                style: action == TeamMemberAction.remove
                                    ? TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      )
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _MemberTag extends StatelessWidget {
  const _MemberTag({
    required this.label,
    required this.icon,
    required this.highlighted,
  });

  final String label;
  final IconData icon;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? AppTheme.primary : AppTheme.navy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

extension on TeamMemberAction {
  String get label => switch (this) {
    TeamMemberAction.makeCoach => 'Hacer entrenador',
    TeamMemberAction.makePlayer => 'Hacer jugador',
    TeamMemberAction.presumeAttending => 'Presumir asistencia',
    TeamMemberAction.presumeAbsent => 'Presumir no asistencia',
    TeamMemberAction.remove => 'Expulsar del equipo',
  };

  IconData get icon => switch (this) {
    TeamMemberAction.makeCoach => Icons.admin_panel_settings_outlined,
    TeamMemberAction.makePlayer => Icons.person_outline,
    TeamMemberAction.presumeAttending => Icons.event_available_outlined,
    TeamMemberAction.presumeAbsent => Icons.event_busy_outlined,
    TeamMemberAction.remove => Icons.person_remove_outlined,
  };
}
