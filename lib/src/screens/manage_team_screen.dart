import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/app_user.dart';
import '../models/player_tag.dart';
import '../models/team_membership.dart';
import '../providers.dart';
import '../repositories/player_tag_repository.dart';
import '../repositories/team_repository.dart';
import '../theme/app_theme.dart';
import '../utils/team_invitation.dart';
import '../widgets/app_notification.dart';
import '../widgets/app_widgets.dart';
import '../widgets/async_state_view.dart';
import '../widgets/player_tag_editor.dart';

enum TeamMemberAction {
  editTags,
  makeCoach,
  makePlayer,
  presumeAttending,
  presumeAbsent,
  remove,
}

List<TeamMemberAction> availableTeamMemberActions({
  required TeamRosterMember currentUser,
  required TeamRosterMember member,
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
    TeamMemberAction.editTags,
    if (!member.managedByCoach) TeamMemberAction.makeCoach,
    member.attendancePresumption == AttendancePresumption.attending
        ? TeamMemberAction.presumeAbsent
        : TeamMemberAction.presumeAttending,
    TeamMemberAction.remove,
  ];
}

class ManageTeamScreen extends ConsumerStatefulWidget {
  const ManageTeamScreen({super.key});

  @override
  ConsumerState<ManageTeamScreen> createState() => _ManageTeamScreenState();
}

class _ManageTeamScreenState extends ConsumerState<ManageTeamScreen> {
  String? _busyMemberId;
  bool _addingPlayer = false;
  bool _busyTags = false;

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentMembershipProvider);
    if (currentUser == null) {
      return const AppLoadingView();
    }
    final teamId = currentUser.teamId;
    final repository = ref.watch(teamRepositoryProvider);
    // Tags are coach-only: never subscribe to them for players.
    final tagsState = currentUser.isCoach
        ? ref.watch(playerTagsProvider(teamId))
        : null;
    final assignmentsState = currentUser.isCoach
        ? ref.watch(playerTagAssignmentsProvider(teamId))
        : null;
    final tags = tagsState?.value ?? const <PlayerTag>[];
    final assignments =
        assignmentsState?.value ?? const <String, List<String>>{};
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
            return StreamBuilder<List<TeamRosterMember>>(
              stream: repository.watchTeamMembers(teamId),
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
                // Members are already active-only, so this counts active
                // players.
                final tagCounts = countMembersByTag(
                  memberIds: players.map((player) => player.id),
                  assignments: assignments,
                  tags: tags,
                );
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
                    if (tagsState != null && assignmentsState != null) ...[
                      const SizedBox(height: 18),
                      PlayerTagCatalogCard(
                        tags: tags,
                        counts: tagCounts,
                        loading:
                            !tagsState.hasValue || !assignmentsState.hasValue,
                        hasError:
                            tagsState.hasError || assignmentsState.hasError,
                        busy: _busyTags,
                        onCreate: () => _createTag(tags),
                        onTagSelected: (tag) => _showTagOptions(
                          tag,
                          tags,
                          tagCounts[tag.id] ?? 0,
                          players: players,
                          assignments: assignments,
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    _MemberSection(
                      title: 'Entrenadores',
                      count: coaches.length,
                      members: coaches,
                      currentUser: currentUser,
                      team: team,
                      busyMemberId: _busyMemberId,
                      onAction: _handleAction,
                    ),
                    const SizedBox(height: 26),
                    _MemberSection(
                      title: 'Jugadores',
                      count: players.length,
                      members: players,
                      currentUser: currentUser,
                      team: team,
                      busyMemberId: _busyMemberId,
                      onAction: _handleAction,
                      tags: tags,
                      tagAssignments: assignments,
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
                QrImageView(
                  data: buildTeamInviteUrl(team.joinCode),
                  version: QrVersions.auto,
                  size: 180,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(8),
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
    final currentUser = ref.read(currentMembershipProvider);
    if (currentUser == null) {
      return;
    }
    final fullName = await showManagedPlayerNameDialog(context);
    if (fullName == null || !mounted) {
      return;
    }

    setState(() => _addingPlayer = true);
    try {
      await ref
          .read(teamRepositoryProvider)
          .createManagedPlayer(
            teamId: currentUser.teamId,
            actingUserId: currentUser.id,
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

  Future<void> _handleAction(
    TeamRosterMember member,
    TeamMemberAction action,
  ) async {
    final currentUser = ref.read(currentMembershipProvider);
    if (currentUser == null) {
      return;
    }
    if (action == TeamMemberAction.editTags) {
      await _editMemberTags(member);
      return;
    }
    final confirmed = await _confirmAction(member, action);
    if (!confirmed || !mounted) {
      return;
    }

    setState(() => _busyMemberId = member.id);
    try {
      final repository = ref.read(teamRepositoryProvider);
      switch (action) {
        case TeamMemberAction.editTags:
          // Handled by _editMemberTags before reaching this point.
          return;
        case TeamMemberAction.makeCoach:
          await repository.updateMemberRole(
            teamId: currentUser.teamId,
            memberId: member.id,
            actingUserId: currentUser.id,
            role: UserRole.admin,
          );
          break;
        case TeamMemberAction.makePlayer:
          await repository.updateMemberRole(
            teamId: currentUser.teamId,
            memberId: member.id,
            actingUserId: currentUser.id,
            role: UserRole.player,
          );
          break;
        case TeamMemberAction.presumeAttending:
          await repository.updateAttendancePresumption(
            teamId: currentUser.teamId,
            memberId: member.id,
            actingUserId: currentUser.id,
            value: AttendancePresumption.attending,
          );
          break;
        case TeamMemberAction.presumeAbsent:
          await repository.updateAttendancePresumption(
            teamId: currentUser.teamId,
            memberId: member.id,
            actingUserId: currentUser.id,
            value: AttendancePresumption.absent,
          );
          break;
        case TeamMemberAction.remove:
          await repository.removeMember(
            teamId: currentUser.teamId,
            memberId: member.id,
            actingUserId: currentUser.id,
          );
          break;
      }
      if (mounted) {
        showAppNotification(
          context,
          message: switch (action) {
            TeamMemberAction.editTags =>
              'Etiquetas de ${member.fullName} actualizadas.',
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

  Future<void> _editMemberTags(TeamRosterMember member) async {
    final currentUser = ref.read(currentMembershipProvider);
    if (currentUser == null || !currentUser.isCoach) {
      return;
    }
    final teamId = currentUser.teamId;
    final tagsState = ref.read(playerTagsProvider(teamId));
    final assignmentsState = ref.read(playerTagAssignmentsProvider(teamId));
    if (!tagsState.hasValue || !assignmentsState.hasValue) {
      showAppNotification(
        context,
        message: 'Las etiquetas aún no están disponibles. Inténtalo de nuevo.',
        type: AppNotificationType.error,
      );
      return;
    }
    final catalog = tagsState.requireValue;
    final initialTagIds = tagIdsFor(
      memberId: member.id,
      assignments: assignmentsState.requireValue,
      tags: catalog,
    );
    final repository = ref.read(playerTagRepositoryProvider);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: PlayerTagEditor(
          playerName: member.fullName,
          catalog: catalog,
          initialTagIds: initialTagIds,
          onCreateTag: (name, existing) async {
            try {
              final id = await repository.createTag(
                teamId: teamId,
                name: name,
                actingUserId: currentUser.id,
                existing: existing,
              );
              return PlayerTag(id: id, name: name.trim());
            } on FirebaseException {
              throw const PlayerTagException('No se pudo crear la etiqueta.');
            }
          },
          onSave: (tagIds, latestCatalog) async {
            try {
              await repository.setMemberTags(
                teamId: teamId,
                memberId: member.id,
                tagIds: tagIds,
                catalog: latestCatalog,
                actingUserId: currentUser.id,
              );
              if (sheetContext.mounted) {
                Navigator.of(sheetContext).pop(true);
              }
            } on PlayerTagException catch (error) {
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
                  message: 'No se pudieron guardar las etiquetas.',
                  type: AppNotificationType.error,
                );
              }
            }
          },
        ),
      ),
    );
    if (saved == true && mounted) {
      showAppNotification(
        context,
        message: 'Etiquetas de ${member.fullName} actualizadas.',
        type: AppNotificationType.success,
      );
    }
  }

  Future<void> _createTag(List<PlayerTag> tags) async {
    final currentUser = ref.read(currentMembershipProvider);
    if (currentUser == null) {
      return;
    }
    final name = await showPlayerTagNameDialog(context, existing: tags);
    if (name == null || !mounted) {
      return;
    }
    await _runTagOperation(
      () => ref
          .read(playerTagRepositoryProvider)
          .createTag(
            teamId: currentUser.teamId,
            name: name,
            actingUserId: currentUser.id,
            existing: tags,
          ),
      successMessage: 'Etiqueta «$name» creada.',
      errorMessage: 'No se pudo crear la etiqueta.',
    );
  }

  Future<void> _showTagOptions(
    PlayerTag tag,
    List<PlayerTag> tags,
    int playerCount, {
    required List<TeamRosterMember> players,
    required PlayerTagAssignments assignments,
  }) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                tag.name,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              subtitle: Text(
                playerCount == 1 ? '1 jugador' : '$playerCount jugadores',
              ),
            ),
            ListTile(
              key: const ValueKey('assign-player-tag'),
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Asignar a jugadores…'),
              onTap: () => Navigator.pop(sheetContext, 'assign'),
            ),
            ListTile(
              key: const ValueKey('rename-player-tag'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Renombrar'),
              onTap: () => Navigator.pop(sheetContext, 'rename'),
            ),
            ListTile(
              key: const ValueKey('delete-player-tag'),
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                'Eliminar',
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (choice == 'assign') {
      await _assignTagToPlayers(tag, tags, players, assignments);
    } else if (choice == 'rename') {
      await _renameTag(tag, tags);
    } else if (choice == 'delete') {
      await _deleteTag(tag, playerCount);
    }
  }

  Future<void> _assignTagToPlayers(
    PlayerTag tag,
    List<PlayerTag> tags,
    List<TeamRosterMember> players,
    PlayerTagAssignments assignments,
  ) async {
    final currentUser = ref.read(currentMembershipProvider);
    if (currentUser == null) {
      return;
    }
    final initialMemberIds = {
      for (final player in players)
        if (tagIdsFor(
          memberId: player.id,
          assignments: assignments,
          tags: tags,
        ).contains(tag.id))
          player.id,
    };
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => PlayerTagMembersEditor(
        tag: tag,
        players: [
          for (final player in players)
            (
              id: player.id,
              name: player.fullName,
              atLimit: isAtTagLimitFor(
                memberId: player.id,
                tagId: tag.id,
                assignments: assignments,
                tags: tags,
              ),
            ),
        ],
        initialMemberIds: initialMemberIds,
        onSave: (added, removed) async {
          try {
            await ref
                .read(playerTagRepositoryProvider)
                .setTagMembers(
                  teamId: currentUser.teamId,
                  tagId: tag.id,
                  addMemberIds: added,
                  removeMemberIds: removed,
                  actingUserId: currentUser.id,
                );
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop(true);
            }
          } on FirebaseException {
            if (mounted) {
              showAppNotification(
                context,
                message: 'No se pudieron asignar las etiquetas.',
                type: AppNotificationType.error,
              );
            }
          }
        },
      ),
    );
    if (saved == true && mounted) {
      showAppNotification(
        context,
        message: 'Etiqueta «${tag.name}» actualizada.',
        type: AppNotificationType.success,
      );
    }
  }

  Future<void> _renameTag(PlayerTag tag, List<PlayerTag> tags) async {
    final currentUser = ref.read(currentMembershipProvider);
    if (currentUser == null) {
      return;
    }
    final name = await showPlayerTagNameDialog(
      context,
      existing: tags,
      title: 'Renombrar etiqueta',
      confirmLabel: 'Guardar',
      initialName: tag.name,
      renamingTagId: tag.id,
    );
    if (name == null || name == tag.name || !mounted) {
      return;
    }
    await _runTagOperation(
      () => ref
          .read(playerTagRepositoryProvider)
          .renameTag(
            teamId: currentUser.teamId,
            tagId: tag.id,
            name: name,
            existing: tags,
          ),
      successMessage: 'Etiqueta renombrada a «$name».',
      errorMessage: 'No se pudo renombrar la etiqueta.',
    );
  }

  Future<void> _deleteTag(PlayerTag tag, int playerCount) async {
    final currentUser = ref.read(currentMembershipProvider);
    if (currentUser == null) {
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.delete_outline),
            title: Text('Eliminar «${tag.name}»'),
            content: Text(
              playerCount == 1
                  ? 'Se quitará de 1 jugador.'
                  : 'Se quitará de $playerCount jugadores.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                key: const ValueKey('confirm-delete-player-tag'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }
    await _runTagOperation(
      () => ref
          .read(playerTagRepositoryProvider)
          .deleteTag(
            teamId: currentUser.teamId,
            tagId: tag.id,
            actingUserId: currentUser.id,
          ),
      successMessage: 'Etiqueta «${tag.name}» eliminada.',
      errorMessage: 'No se pudo eliminar la etiqueta.',
    );
  }

  Future<void> _runTagOperation(
    Future<void> Function() operation, {
    required String successMessage,
    required String errorMessage,
  }) async {
    setState(() => _busyTags = true);
    try {
      await operation();
      if (mounted) {
        showAppNotification(
          context,
          message: successMessage,
          type: AppNotificationType.success,
        );
      }
    } on PlayerTagException catch (error) {
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
          message: errorMessage,
          type: AppNotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyTags = false);
      }
    }
  }

  Future<bool> _confirmAction(
    TeamRosterMember member,
    TeamMemberAction action,
  ) async {
    final title = switch (action) {
      TeamMemberAction.editTags => 'Etiquetas',
      TeamMemberAction.makeCoach => 'Hacer entrenador',
      TeamMemberAction.makePlayer => 'Hacer jugador',
      TeamMemberAction.presumeAttending => 'Presumir asistencia',
      TeamMemberAction.presumeAbsent => 'Presumir no asistencia',
      TeamMemberAction.remove => 'Expulsar del equipo',
    };
    final message = switch (action) {
      TeamMemberAction.editTags => 'Asigna etiquetas a ${member.fullName}.',
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
    this.tags = const [],
    this.tagAssignments = const {},
  });

  final String title;
  final int count;
  final List<TeamRosterMember> members;
  final TeamRosterMember currentUser;
  final Team team;
  final String? busyMemberId;
  final void Function(TeamRosterMember member, TeamMemberAction action)
  onAction;
  final List<PlayerTag> tags;
  final PlayerTagAssignments tagAssignments;

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
                tags: tags,
                tagAssignments: tagAssignments,
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
    this.tags = const [],
    this.tagAssignments = const {},
    super.key,
  });

  final TeamRosterMember member;
  final TeamRosterMember currentUser;
  final Team team;
  final bool busy;
  final ValueChanged<TeamMemberAction> onAction;

  /// The team's tag catalog; only provided to coaches.
  final List<PlayerTag> tags;
  final PlayerTagAssignments tagAssignments;

  @override
  Widget build(BuildContext context) {
    final actions = availableTeamMemberActions(
      currentUser: currentUser,
      member: member,
      team: team,
    );
    final isOwner = team.createdBy == member.id;
    final isCurrentUser = currentUser.id == member.id;
    final tagNames = {for (final tag in tags) tag.id: tag.name};
    final memberTagIds = member.isCoach
        ? const <String>[]
        : tagIdsFor(
            memberId: member.id,
            assignments: tagAssignments,
            tags: tags,
          );
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
                      for (final tagId in memberTagIds)
                        _MemberTag(
                          label: tagNames[tagId]!,
                          icon: Icons.label_outline,
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
    TeamMemberAction.editTags => 'Etiquetas…',
    TeamMemberAction.makeCoach => 'Hacer entrenador',
    TeamMemberAction.makePlayer => 'Hacer jugador',
    TeamMemberAction.presumeAttending => 'Presumir asistencia',
    TeamMemberAction.presumeAbsent => 'Presumir no asistencia',
    TeamMemberAction.remove => 'Expulsar del equipo',
  };

  IconData get icon => switch (this) {
    TeamMemberAction.editTags => Icons.label_outline,
    TeamMemberAction.makeCoach => Icons.admin_panel_settings_outlined,
    TeamMemberAction.makePlayer => Icons.person_outline,
    TeamMemberAction.presumeAttending => Icons.event_available_outlined,
    TeamMemberAction.presumeAbsent => Icons.event_busy_outlined,
    TeamMemberAction.remove => Icons.person_remove_outlined,
  };
}
