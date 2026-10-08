import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/player_tag.dart';

class PlayerTagException implements Exception {
  const PlayerTagException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Coach-only player tags: the catalog at `teams/{teamId}/playerTags` and
/// each member's assignment at `teams/{teamId}/playerTagAssignments`.
///
/// Tags live outside `teamMemberships` on purpose: membership documents are
/// rewritten whole by the client and by Cloud Functions, which would wipe
/// any extra field.
class PlayerTagRepository {
  PlayerTagRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _tags(String teamId) =>
      _firestore.collection('teams').doc(teamId).collection('playerTags');

  CollectionReference<Map<String, dynamic>> _assignments(String teamId) =>
      _firestore
          .collection('teams')
          .doc(teamId)
          .collection('playerTagAssignments');

  /// The team's tag catalog, sorted by name.
  Stream<List<PlayerTag>> watchTags(String teamId) {
    return _tags(teamId).snapshots().map(
      (snapshot) => sortTags(snapshot.docs.map(PlayerTag.fromSnapshot)),
    );
  }

  Stream<PlayerTagAssignments> watchAssignments(String teamId) {
    return _assignments(teamId).snapshots().map(
      (snapshot) => {
        for (final document in snapshot.docs)
          document.id: parseTagIds(document.data()),
      },
    );
  }

  /// Creates a tag and returns its id. [existing] is the current catalog,
  /// used to reject duplicates and enforce [maxTagsPerTeam].
  Future<String> createTag({
    required String teamId,
    required String name,
    required String actingUserId,
    required List<PlayerTag> existing,
  }) async {
    final error = validateTagName(name: name, existing: existing);
    if (error != null) {
      throw PlayerTagException(error);
    }
    final reference = _tags(teamId).doc();
    await reference.set({
      'name': name.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': actingUserId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return reference.id;
  }

  Future<void> renameTag({
    required String teamId,
    required String tagId,
    required String name,
    required List<PlayerTag> existing,
  }) async {
    final error = validateTagName(
      name: name,
      existing: existing,
      renamingTagId: tagId,
    );
    if (error != null) {
      throw PlayerTagException(error);
    }
    await _tags(teamId).doc(tagId).update({
      'name': name.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a tag and removes it from every member that carries it.
  Future<void> deleteTag({
    required String teamId,
    required String tagId,
    required String actingUserId,
  }) async {
    final carriers = await _assignments(
      teamId,
    ).where('tagIds', arrayContains: tagId).get();
    // A batch is capped at 500 writes. The tag is deleted last so a failed
    // cleanup can be retried; readers already ignore ids of deleted tags.
    final documents = carriers.docs;
    for (var start = 0; start < documents.length; start += 450) {
      final batch = _firestore.batch();
      for (final document in documents.skip(start).take(450)) {
        batch.update(document.reference, {
          'tagIds': FieldValue.arrayRemove([tagId]),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': actingUserId,
        });
      }
      await batch.commit();
    }
    await _tags(teamId).doc(tagId).delete();
  }

  /// Adds [tagId] to [addMemberIds] and removes it from [removeMemberIds],
  /// leaving every other tag of those members untouched. Callers must skip
  /// members that already have [maxTagsPerPlayer] tags; the rules reject a
  /// batch that would push anyone over the limit.
  Future<void> setTagMembers({
    required String teamId,
    required String tagId,
    required Iterable<String> addMemberIds,
    required Iterable<String> removeMemberIds,
    required String actingUserId,
  }) async {
    final writes = [
      for (final memberId in addMemberIds)
        (memberId, FieldValue.arrayUnion([tagId])),
      for (final memberId in removeMemberIds)
        (memberId, FieldValue.arrayRemove([tagId])),
    ];
    for (var start = 0; start < writes.length; start += 450) {
      final batch = _firestore.batch();
      for (final (memberId, change) in writes.skip(start).take(450)) {
        batch.set(_assignments(teamId).doc(memberId), {
          'tagIds': change,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': actingUserId,
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  /// Replaces [memberId]'s tags with [tagIds], dropping ids that are not in
  /// [catalog] (e.g. tags deleted meanwhile).
  Future<void> setMemberTags({
    required String teamId,
    required String memberId,
    required List<String> tagIds,
    required List<PlayerTag> catalog,
    required String actingUserId,
  }) async {
    final valid = catalog.map((tag) => tag.id).toSet();
    final cleaned = tagIds.toSet().where(valid.contains).toList();
    if (cleaned.length > maxTagsPerPlayer) {
      throw const PlayerTagException(
        'Un jugador puede tener como máximo $maxTagsPerPlayer etiquetas.',
      );
    }
    await _assignments(teamId).doc(memberId).set({
      'tagIds': cleaned,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': actingUserId,
    });
  }
}
