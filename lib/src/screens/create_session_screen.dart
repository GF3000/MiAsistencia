import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../widgets/app_notification.dart';
import '../widgets/app_widgets.dart';

class CreateSessionScreen extends ConsumerStatefulWidget {
  const CreateSessionScreen({
    required this.teamId,
    this.initialDate,
    super.key,
  });

  final String teamId;
  final DateTime? initialDate;

  @override
  ConsumerState<CreateSessionScreen> createState() =>
      _CreateSessionScreenState();
}

class _CreateSessionScreenState extends ConsumerState<CreateSessionScreen> {
  final _titleController = TextEditingController(text: 'Entrenamiento');
  late DateTime _date;
  TimeOfDay _startTime = const TimeOfDay(hour: 19, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 20, minute: 30);
  bool _recurring = false;
  int _weeks = 4;
  final Set<int> _weekdays = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _date = DateUtils.dateOnly(
      widget.initialDate ?? DateTime.now().add(const Duration(days: 1)),
    );
    _weekdays.add(_date.weekday);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final defaultFirstDate = DateUtils.dateOnly(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _date.isBefore(defaultFirstDate) ? _date : defaultFirstDate,
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (selected != null) {
      setState(() {
        _date = selected;
        if (!_recurring) {
          _weekdays
            ..clear()
            ..add(selected.weekday);
        }
      });
    }
  }

  Future<void> _selectTime({required bool start}) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
    );
    if (selected != null) {
      setState(() {
        if (start) {
          _startTime = selected;
        } else {
          _endTime = selected;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      _showMessage(
        'Escribe un título para la sesión.',
        type: AppNotificationType.warning,
      );
      return;
    }
    if (_recurring && _weekdays.isEmpty) {
      _showMessage(
        'Selecciona al menos un día de la semana.',
        type: AppNotificationType.warning,
      );
      return;
    }
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    if (endMinutes <= startMinutes) {
      _showMessage(
        'La hora de fin debe ser posterior a la de inicio.',
        type: AppNotificationType.warning,
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final count = await ref
          .read(sessionRepositoryProvider)
          .createSessions(
            teamId: widget.teamId,
            title: _titleController.text,
            firstDate: _date,
            startTime: DateTime(2000, 1, 1, _startTime.hour, _startTime.minute),
            endTime: DateTime(2000, 1, 1, _endTime.hour, _endTime.minute),
            weekdays: _recurring ? _weekdays : {_date.weekday},
            weeks: _recurring ? _weeks : 1,
          );
      if (!mounted) {
        return;
      }
      Navigator.pop(context);
      showAppNotification(
        context,
        message: count == 1
            ? 'Sesión creada.'
            : 'Se han creado $count sesiones.',
        type: AppNotificationType.success,
      );
    } on FirebaseException {
      _showMessage('No se pudieron crear las sesiones.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showMessage(
    String message, {
    AppNotificationType type = AppNotificationType.error,
  }) {
    if (mounted) {
      showAppNotification(context, message: message, type: type);
    }
  }

  @override
  Widget build(BuildContext context) {
    const weekdayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva sesión')),
      body: AppPageBody(
        maxWidth: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Título',
                prefixIcon: Icon(Icons.sports_basketball_outlined),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    minTileHeight: 62,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Fecha'),
                    subtitle: Text(formatSpanishDate(_date)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _selectDate,
                  ),
                  const Divider(height: 1),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          minTileHeight: 62,
                          leading: const Icon(Icons.schedule_outlined),
                          title: const Text('Inicio'),
                          subtitle: Text(_startTime.format(context)),
                          onTap: () => _selectTime(start: true),
                        ),
                      ),
                      Expanded(
                        child: ListTile(
                          minTileHeight: 62,
                          title: const Text('Fin'),
                          subtitle: Text(_endTime.format(context)),
                          onTap: () => _selectTime(start: false),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Repetir sesión'),
                      subtitle: const Text(
                        'Crea varias sesiones con el mismo horario.',
                      ),
                      value: _recurring,
                      onChanged: (value) => setState(() {
                        _recurring = value;
                        if (_weekdays.isEmpty) {
                          _weekdays.add(_date.weekday);
                        }
                      }),
                    ),
                    if (_recurring) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Días de la semana',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: List.generate(7, (index) {
                          final weekday = index + 1;
                          return FilterChip(
                            label: Text(weekdayLabels[index]),
                            selected: _weekdays.contains(weekday),
                            onSelected: (selected) => setState(() {
                              selected
                                  ? _weekdays.add(weekday)
                                  : _weekdays.remove(weekday);
                            }),
                          );
                        }),
                      ),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<int>(
                        initialValue: _weeks,
                        decoration: const InputDecoration(
                          labelText: 'Duración de la serie',
                        ),
                        items: const [2, 4, 6, 8, 12, 16, 24, 52]
                            .map(
                              (weeks) => DropdownMenuItem(
                                value: weeks,
                                child: Text('$weeks semanas'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _weeks = value ?? 4),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.add),
              label: Text(_busy ? 'Creando…' : 'Crear sesión'),
            ),
          ],
        ),
      ),
    );
  }
}
