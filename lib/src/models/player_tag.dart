import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/search_text.dart';

/// Maximum number of tags a single player can carry. Mirrored by the
/// `playerTagAssignments` security rule.
const maxTagsPerPlayer = 5;

/// Maximum number of tags in a team's catalog. Firestore rules cannot count
/// documents, so this one is only enforced by the client.
const maxTagsPerTeam = 30;

/// Maximum length of a tag name. Mirrored by the `playerTags` security rule.
const maxTagNameLength = 24;

/// A coach-defined label (e.g. "Portero", "Zurdo") stored at
/// `teams/{teamId}/playerTags/{tagId}`. Only coaches can read or write tags.
class PlayerTag {
  const PlayerTag({required this.id, required this.name});

  final String id;
  final String name;

  factory PlayerTag.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return PlayerTag(id: snapshot.id, name: data['name'] as String? ?? '');
  }
}

/// Tag ids assigned to each roster member, keyed by member id. Read from
/// `teams/{teamId}/playerTagAssignments/{memberId}`; a member without a
/// document has no tags.
typedef PlayerTagAssignments = Map<String, List<String>>;

List<String> parseTagIds(Map<String, dynamic>? data) {
  return (data?['tagIds'] as List<dynamic>? ?? const [])
      .whereType<String>()
      .toList();
}

/// Sorts [tags] by name, ignoring case and accents.
List<PlayerTag> sortTags(Iterable<PlayerTag> tags) {
  return [...tags]..sort(
    (left, right) => normalizeSearchText(
      left.name,
    ).compareTo(normalizeSearchText(right.name)),
  );
}

/// The tag ids of [memberId] that still exist in [tags], in catalog order.
/// Ids of deleted tags are ignored.
List<String> tagIdsFor({
  required String memberId,
  required PlayerTagAssignments assignments,
  required Iterable<PlayerTag> tags,
}) {
  final assigned = assignments[memberId]?.toSet() ?? const <String>{};
  return [
    for (final tag in tags)
      if (assigned.contains(tag.id)) tag.id,
  ];
}

/// Whether [memberId] cannot receive [tagId] because they already carry
/// [maxTagsPerPlayer] other tags.
bool isAtTagLimitFor({
  required String memberId,
  required String tagId,
  required PlayerTagAssignments assignments,
  required Iterable<PlayerTag> tags,
}) {
  final current = tagIdsFor(
    memberId: memberId,
    assignments: assignments,
    tags: tags,
  );
  return !current.contains(tagId) && current.length >= maxTagsPerPlayer;
}

/// How many of [memberIds] carry each tag in [tags]. Tags with no members
/// are included with a count of 0.
Map<String, int> countMembersByTag({
  required Iterable<String> memberIds,
  required PlayerTagAssignments assignments,
  required Iterable<PlayerTag> tags,
}) {
  final counts = {for (final tag in tags) tag.id: 0};
  for (final memberId in memberIds) {
    for (final tagId in assignments[memberId]?.toSet() ?? const <String>{}) {
      final current = counts[tagId];
      if (current != null) {
        counts[tagId] = current + 1;
      }
    }
  }
  return counts;
}

/// Returns an error message when [name] is not a valid new name for a tag in
/// [existing], or null when it is. [renamingTagId] excludes the tag being
/// renamed from the duplicate check.
String? validateTagName({
  required String name,
  required Iterable<PlayerTag> existing,
  String? renamingTagId,
}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return 'Escribe un nombre para la etiqueta.';
  }
  if (trimmed.length > maxTagNameLength) {
    return 'El nombre no puede superar $maxTagNameLength caracteres.';
  }
  final normalized = normalizeSearchText(trimmed);
  final duplicate = existing.any(
    (tag) =>
        tag.id != renamingTagId && normalizeSearchText(tag.name) == normalized,
  );
  if (duplicate) {
    return 'Ya existe una etiqueta con ese nombre.';
  }
  if (renamingTagId == null && existing.length >= maxTagsPerTeam) {
    return 'El equipo ya tiene el máximo de $maxTagsPerTeam etiquetas.';
  }
  return null;
}
