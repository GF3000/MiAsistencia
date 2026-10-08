import 'package:flutter/material.dart';

import '../models/player_tag.dart';
import '../repositories/player_tag_repository.dart';
import '../theme/app_theme.dart';
import '../utils/search_text.dart';

/// Coach-only card listing the team's tag catalog with how many players
/// carry each tag.
class PlayerTagCatalogCard extends StatelessWidget {
  const PlayerTagCatalogCard({
    required this.tags,
    required this.counts,
    required this.onCreate,
    required this.onTagSelected,
    this.loading = false,
    this.hasError = false,
    this.busy = false,
    super.key,
  });

  final List<PlayerTag> tags;

  /// Players carrying each tag, keyed by tag id.
  final Map<String, int> counts;
  final VoidCallback onCreate;
  final ValueChanged<PlayerTag> onTagSelected;
  final bool loading;
  final bool hasError;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final mutedStyle = TextStyle(color: Colors.blueGrey.shade600, fontSize: 13);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.label_outline, color: AppTheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Etiquetas de jugadores',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('create-player-tag'),
                  onPressed: busy || loading || hasError ? null : onCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva etiqueta'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (hasError)
              Text(
                'No se pudieron cargar las etiquetas.',
                style: mutedStyle.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              )
            else if (loading)
              const Align(
                alignment: Alignment.centerLeft,
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (tags.isEmpty)
              Text(
                'Crea etiquetas como «Portero» o «Zurdo» para agrupar '
                'jugadores en las sesiones.',
                style: mutedStyle,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in tags)
                    ActionChip(
                      key: ValueKey('player-tag-${tag.id}'),
                      avatar: const Icon(Icons.label_outline, size: 16),
                      label: Text('${tag.name} · ${counts[tag.id] ?? 0}'),
                      tooltip: 'Renombrar o eliminar «${tag.name}»',
                      onPressed: busy ? null : () => onTagSelected(tag),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a tag name, validated with [validateTagName] against [existing].
Future<String?> showPlayerTagNameDialog(
  BuildContext context, {
  required List<PlayerTag> existing,
  String title = 'Nueva etiqueta',
  String confirmLabel = 'Crear',
  String initialName = '',
  String? renamingTagId,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _PlayerTagNameDialog(
      existing: existing,
      title: title,
      confirmLabel: confirmLabel,
      initialName: initialName,
      renamingTagId: renamingTagId,
    ),
  );
}

class _PlayerTagNameDialog extends StatefulWidget {
  const _PlayerTagNameDialog({
    required this.existing,
    required this.title,
    required this.confirmLabel,
    required this.initialName,
    required this.renamingTagId,
  });

  final List<PlayerTag> existing;
  final String title;
  final String confirmLabel;
  final String initialName;
  final String? renamingTagId;

  @override
  State<_PlayerTagNameDialog> createState() => _PlayerTagNameDialogState();
}

class _PlayerTagNameDialogState extends State<_PlayerTagNameDialog> {
  late final _nameController = TextEditingController(text: widget.initialName);
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final error = validateTagName(
      name: name,
      existing: widget.existing,
      renamingTagId: widget.renamingTagId,
    );
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.label_outline),
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('player-tag-name'),
        controller: _nameController,
        autofocus: true,
        maxLength: maxTagNameLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'Nombre',
          hintText: 'Ej.: Portero',
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
          key: const ValueKey('confirm-player-tag-name'),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Multi-select editor for one player's tags, shown in a bottom sheet.
///
/// [onCreateTag] creates a tag in the catalog and returns it; it may throw a
/// [PlayerTagException] whose message is shown inline. [onSave] receives the
/// selected tag ids (in catalog order) and the catalog including any tags
/// created here.
class PlayerTagEditor extends StatefulWidget {
  const PlayerTagEditor({
    required this.playerName,
    required this.catalog,
    required this.initialTagIds,
    required this.onCreateTag,
    required this.onSave,
    super.key,
  });

  final String playerName;
  final List<PlayerTag> catalog;
  final List<String> initialTagIds;
  final Future<PlayerTag> Function(String name, List<PlayerTag> catalog)
  onCreateTag;
  final Future<void> Function(List<String> tagIds, List<PlayerTag> catalog)
  onSave;

  @override
  State<PlayerTagEditor> createState() => _PlayerTagEditorState();
}

class _PlayerTagEditorState extends State<PlayerTagEditor> {
  late List<PlayerTag> _catalog = sortTags(widget.catalog);
  late final Set<String> _selected = {
    for (final id in widget.initialTagIds)
      if (widget.catalog.any((tag) => tag.id == id)) id,
  };
  final _newTagController = TextEditingController();
  String? _newTagError;
  bool _creating = false;
  bool _saving = false;

  bool get _atLimit => _selected.length >= maxTagsPerPlayer;

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  void _toggle(String tagId, bool selected) {
    setState(() {
      if (selected) {
        if (!_atLimit) {
          _selected.add(tagId);
        }
      } else {
        _selected.remove(tagId);
      }
    });
  }

  Future<void> _createTag() async {
    final name = _newTagController.text.trim();
    final error = validateTagName(name: name, existing: _catalog);
    if (error != null) {
      setState(() => _newTagError = error);
      return;
    }
    setState(() {
      _creating = true;
      _newTagError = null;
    });
    try {
      final tag = await widget.onCreateTag(name, _catalog);
      if (!mounted) {
        return;
      }
      setState(() {
        _catalog = sortTags([..._catalog, tag]);
        if (!_atLimit) {
          _selected.add(tag.id);
        }
        _newTagController.clear();
      });
    } on PlayerTagException catch (error) {
      if (mounted) {
        setState(() => _newTagError = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _newTagError = 'No se pudo crear la etiqueta.');
      }
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave([
        for (final tag in _catalog)
          if (_selected.contains(tag.id)) tag.id,
      ], _catalog);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _creating || _saving;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Etiquetas de ${widget.playerName}',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              Text(
                '${_selected.length}/$maxTagsPerPlayer',
                key: const ValueKey('player-tag-counter'),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _atLimit ? AppTheme.primary : Colors.blueGrey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _atLimit
                ? 'Máximo $maxTagsPerPlayer etiquetas'
                : 'Selecciona hasta $maxTagsPerPlayer etiquetas.',
            key: const ValueKey('player-tag-helper'),
            style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 14),
          if (_catalog.isEmpty)
            Text(
              'Todavía no hay etiquetas. Crea la primera aquí debajo.',
              style: TextStyle(color: Colors.blueGrey.shade600),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in _catalog)
                      FilterChip(
                        key: ValueKey('player-tag-chip-${tag.id}'),
                        label: Text(tag.name),
                        selected: _selected.contains(tag.id),
                        onSelected:
                            busy || (_atLimit && !_selected.contains(tag.id))
                            ? null
                            : (selected) => _toggle(tag.id, selected),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('player-tag-new-name'),
                  controller: _newTagController,
                  enabled: !busy,
                  maxLength: maxTagNameLength,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Nueva etiqueta',
                    isDense: true,
                    errorText: _newTagError,
                  ),
                  onChanged: (_) {
                    if (_newTagError != null) {
                      setState(() => _newTagError = null);
                    }
                  },
                  onSubmitted: (_) => _createTag(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const ValueKey('player-tag-add'),
                tooltip: 'Crear etiqueta',
                onPressed: busy ? null : _createTag,
                icon: _creating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('player-tag-save'),
            onPressed: busy ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

/// A player that can be picked in [PlayerTagMembersEditor].
typedef TagMemberOption = ({String id, String name, bool atLimit});

/// Coach-only sheet to give one tag to many players at once. Players that
/// already carry [maxTagsPerPlayer] other tags can't be checked.
class PlayerTagMembersEditor extends StatefulWidget {
  const PlayerTagMembersEditor({
    required this.tag,
    required this.players,
    required this.initialMemberIds,
    required this.onSave,
    super.key,
  });

  final PlayerTag tag;
  final List<TagMemberOption> players;
  final Set<String> initialMemberIds;

  /// Receives the members to add the tag to and to remove it from.
  final Future<void> Function(Set<String> added, Set<String> removed) onSave;

  @override
  State<PlayerTagMembersEditor> createState() => _PlayerTagMembersEditorState();
}

class _PlayerTagMembersEditorState extends State<PlayerTagMembersEditor> {
  late final Set<String> _selected = {...widget.initialMemberIds};
  String _query = '';
  bool _saving = false;

  Set<String> get _added => _selected.difference(widget.initialMemberIds);
  Set<String> get _removed => widget.initialMemberIds.difference(_selected);

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_added, _removed);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showSearch = widget.players.length > playerSearchThreshold;
    final visible = widget.players
        .where((player) => matchesSearchQuery(player.name, _query.trim()))
        .toList();
    final changes = _added.length + _removed.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Asignar «${widget.tag.name}»',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              Text(
                '${_selected.length} seleccionado'
                '${_selected.length == 1 ? '' : 's'}',
                key: const ValueKey('tag-members-counter'),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.blueGrey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (showSearch)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                key: const ValueKey('tag-members-search'),
                decoration: const InputDecoration(
                  hintText: 'Buscar jugador',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          if (widget.players.isEmpty)
            Text(
              'No hay jugadores en el equipo.',
              style: TextStyle(color: Colors.blueGrey.shade600),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final player in visible)
                    CheckboxListTile(
                      key: ValueKey('tag-member-${player.id}'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(player.name),
                      subtitle: player.atLimit
                          ? const Text('Ya tiene $maxTagsPerPlayer etiquetas')
                          : null,
                      value: _selected.contains(player.id),
                      onChanged: _saving || player.atLimit
                          ? null
                          : (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(player.id);
                              } else {
                                _selected.remove(player.id);
                              }
                            }),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('tag-members-save'),
            onPressed: _saving || changes == 0 ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
