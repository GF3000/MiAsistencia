import 'package:flutter/material.dart';

import '../models/attendance.dart';

Future<String?> showOptionalAttendanceNoteDialog({
  required BuildContext context,
  required AttendanceStatus status,
  String initialNote = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) =>
        _OptionalAttendanceNoteDialog(status: status, initialNote: initialNote),
  );
}

class _OptionalAttendanceNoteDialog extends StatefulWidget {
  const _OptionalAttendanceNoteDialog({
    required this.status,
    required this.initialNote,
  });

  final AttendanceStatus status;
  final String initialNote;

  @override
  State<_OptionalAttendanceNoteDialog> createState() =>
      _OptionalAttendanceNoteDialogState();
}

class _OptionalAttendanceNoteDialogState
    extends State<_OptionalAttendanceNoteDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(status.icon, color: status.color, size: 34),
              const SizedBox(height: 12),
              Text(
                status.playerLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 18),
              TextField(
                key: const ValueKey('quick-attendance-note'),
                controller: _controller,
                autofocus: true,
                maxLength: 180,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  hintText: 'Ej. Llegaré 15 minutos tarde',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Omitir'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _controller.text),
                    child: const Text('Guardar nota'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerAttendanceNoteField extends StatefulWidget {
  const PlayerAttendanceNoteField({
    required this.note,
    required this.onSave,
    this.enabled = true,
    this.saving = false,
    super.key,
  });

  final String note;
  final bool enabled;
  final bool saving;
  final Future<void> Function(String note) onSave;

  @override
  State<PlayerAttendanceNoteField> createState() =>
      _PlayerAttendanceNoteFieldState();
}

class _PlayerAttendanceNoteFieldState extends State<PlayerAttendanceNoteField> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  bool get _hasChanges => _controller.text.trim() != widget.note.trim();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.note);
  }

  @override
  void didUpdateWidget(covariant PlayerAttendanceNoteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note != widget.note && !_focusNode.hasFocus) {
      _controller.text = widget.note;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Notas', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('player-attendance-note'),
          controller: _controller,
          focusNode: _focusNode,
          readOnly: !widget.enabled,
          maxLength: widget.enabled ? 180 : null,
          minLines: 2,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: widget.enabled
                ? 'Añade información para tu entrenador'
                : 'Sin notas',
            alignLabelWithHint: true,
          ),
        ),
        if (widget.enabled) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              key: const ValueKey('save-player-attendance-note'),
              onPressed: _hasChanges && !widget.saving
                  ? () => widget.onSave(_controller.text)
                  : null,
              icon: widget.saving
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(widget.saving ? 'Guardando…' : 'Guardar nota'),
            ),
          ),
        ],
      ],
    );
  }
}

class PlayerAttendanceChoices extends StatelessWidget {
  const PlayerAttendanceChoices({
    required this.selectedStatus,
    required this.onSelected,
    this.savingStatus,
    this.enabled = true,
    super.key,
  });

  final AttendanceStatus selectedStatus;
  final AttendanceStatus? savingStatus;
  final bool enabled;
  final ValueChanged<AttendanceStatus> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: AttendanceStatus.playerOptions.map((status) {
        final saving = savingStatus == status;
        return _AttendanceStatusChip(
          key: ValueKey('player-status-${status.firestoreValue}'),
          status: status,
          label: status.playerLabel,
          selected: selectedStatus.playerEquivalent == status,
          onSelected: enabled && savingStatus == null
              ? (_) => onSelected(status)
              : null,
          saving: saving,
        );
      }).toList(),
    );
  }
}

class _AttendanceStatusChip extends StatelessWidget {
  const _AttendanceStatusChip({
    required this.status,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.saving = false,
    super.key,
  });

  final AttendanceStatus status;
  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = selected ? Colors.white : status.color;
    return ChoiceChip(
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      selectedColor: status.color,
      side: BorderSide(
        color: selected ? status.color : const Color(0xFFBCC8C8),
      ),
      labelStyle: TextStyle(
        color: selected
            ? Colors.white
            : Theme.of(context).colorScheme.onSurface,
      ),
      avatar: saving
          ? SizedBox.square(
              dimension: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foregroundColor,
              ),
            )
          : Icon(status.icon, size: 18, color: foregroundColor),
      label: Text(label),
    );
  }
}

Future<AttendanceDraft?> showAttendanceEditor({
  required BuildContext context,
  required AttendanceRecord initialValue,
  required String title,
  bool showCoachOptions = false,
}) {
  return showModalBottomSheet<AttendanceDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _AttendanceEditor(
      initialValue: initialValue,
      title: title,
      showCoachOptions: showCoachOptions,
    ),
  );
}

class _AttendanceEditor extends StatefulWidget {
  const _AttendanceEditor({
    required this.initialValue,
    required this.title,
    required this.showCoachOptions,
  });

  final AttendanceRecord initialValue;
  final String title;
  final bool showCoachOptions;

  @override
  State<_AttendanceEditor> createState() => _AttendanceEditorState();
}

class _AttendanceEditorState extends State<_AttendanceEditor> {
  late AttendanceStatus _status;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _status = widget.initialValue.status == AttendanceStatus.notApplicable
        ? AttendanceStatus.attending
        : widget.showCoachOptions
        ? widget.initialValue.status
        : widget.initialValue.status.playerEquivalent;
    _noteController = TextEditingController(
      text: widget.initialValue.note ?? '',
    );
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade200,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 18),
            _StatusChoices(
              statuses: AttendanceStatus.playerOptions,
              selected: _status,
              perspective: widget.showCoachOptions
                  ? AttendanceLabelPerspective.coach
                  : AttendanceLabelPerspective.player,
              onSelected: (status) => setState(() => _status = status),
            ),
            if (widget.showCoachOptions) ...[
              const SizedBox(height: 22),
              Text(
                'Incidencias del entrenador',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              _StatusChoices(
                statuses: AttendanceStatus.coachOnlyOptions,
                selected: _status,
                perspective: AttendanceLabelPerspective.coach,
                onSelected: (status) => setState(() => _status = status),
              ),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: _noteController,
              maxLength: 180,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Nota opcional',
                hintText: 'Ej. Llego 15 minutos tarde por trabajo',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                AttendanceDraft(status: _status, note: _noteController.text),
              ),
              child: const Text('Guardar estado'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChoices extends StatelessWidget {
  const _StatusChoices({
    required this.statuses,
    required this.selected,
    required this.perspective,
    required this.onSelected,
  });

  final List<AttendanceStatus> statuses;
  final AttendanceStatus selected;
  final AttendanceLabelPerspective perspective;
  final ValueChanged<AttendanceStatus> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: statuses
          .map(
            (status) => _AttendanceStatusChip(
              status: status,
              label: status.labelFor(perspective),
              selected: selected == status,
              onSelected: (_) => onSelected(status),
            ),
          )
          .toList(),
    );
  }
}
