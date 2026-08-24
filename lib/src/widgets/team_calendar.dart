import 'package:flutter/material.dart';

import '../models/team_session.dart';
import '../theme/app_theme.dart';
import 'app_notification.dart';
import 'app_widgets.dart';

class TeamCalendarView extends StatefulWidget {
  const TeamCalendarView({
    required this.sessions,
    required this.onSessionSelected,
    this.onEmptyDateSelected,
    this.initialDate,
    super.key,
  });

  final List<TeamSession> sessions;
  final ValueChanged<TeamSession> onSessionSelected;
  final ValueChanged<DateTime>? onEmptyDateSelected;
  final DateTime? initialDate;

  @override
  State<TeamCalendarView> createState() => _TeamCalendarViewState();
}

class _TeamCalendarViewState extends State<TeamCalendarView> {
  late DateTime _visibleMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final initialDate = widget.initialDate ?? DateTime.now();
    _selectedDate = DateUtils.dateOnly(initialDate);
    _visibleMonth = DateTime(initialDate.year, initialDate.month);
  }

  void _changeMonth(int offset) {
    final month = DateTime(_visibleMonth.year, _visibleMonth.month + offset);
    setState(() {
      _visibleMonth = month;
      _selectedDate = month;
    });
  }

  void _goToToday() {
    final today = DateUtils.dateOnly(DateTime.now());
    setState(() {
      _visibleMonth = DateTime(today.year, today.month);
      _selectedDate = today;
    });
  }

  Future<void> _selectDate(DateTime date) async {
    final normalizedDate = DateUtils.dateOnly(date);
    final sessions =
        widget.sessions
            .where(
              (session) =>
                  DateUtils.isSameDay(session.startTime, normalizedDate),
            )
            .toList()
          ..sort((left, right) => left.startTime.compareTo(right.startTime));

    setState(() {
      _selectedDate = normalizedDate;
      if (normalizedDate.month != _visibleMonth.month ||
          normalizedDate.year != _visibleMonth.year) {
        _visibleMonth = DateTime(normalizedDate.year, normalizedDate.month);
      }
    });

    if (sessions.length == 1) {
      widget.onSessionSelected(sessions.single);
      return;
    }
    if (sessions.isEmpty) {
      final onEmptyDateSelected = widget.onEmptyDateSelected;
      if (onEmptyDateSelected != null) {
        onEmptyDateSelected(normalizedDate);
        return;
      }
      showAppNotification(
        context,
        message: 'No hay sesiones este día.',
        duration: const Duration(seconds: 2),
      );
      return;
    }

    final selectedSession = await showDialog<TeamSession>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          key: const ValueKey('calendar-session-picker'),
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Elige una sesión',
                  style: Theme.of(dialogContext).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  formatSpanishDate(normalizedDate),
                  style: TextStyle(color: Colors.blueGrey.shade600),
                ),
                const SizedBox(height: 18),
                ...sessions.map(
                  (session) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        key: ValueKey('calendar-session-option-${session.id}'),
                        minTileHeight: 64,
                        leading: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            formatTime(dialogContext, session.startTime),
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        title: Text(session.title),
                        subtitle: Text(
                          'Hasta ${formatTime(dialogContext, session.endTime)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(dialogContext, session),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancelar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selectedSession != null && mounted) {
      widget.onSessionSelected(selectedSession);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 820;
        final calendar = Card(
          key: const ValueKey('calendar-month-card'),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isWide ? 22 : 12,
              12,
              isWide ? 22 : 12,
              isWide ? 22 : 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Mes anterior',
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        formatSpanishMonth(_visibleMonth),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton(onPressed: _goToToday, child: const Text('Hoy')),
                    IconButton(
                      tooltip: 'Mes siguiente',
                      onPressed: () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const _WeekdayHeader(),
                const SizedBox(height: 8),
                _MonthGrid(
                  visibleMonth: _visibleMonth,
                  selectedDate: _selectedDate,
                  sessions: widget.sessions,
                  isWide: isWide,
                  onSelected: _selectDate,
                ),
              ],
            ),
          ),
        );
        return SizedBox(
          key: ValueKey(
            isWide ? 'calendar-wide-layout' : 'calendar-compact-layout',
          ),
          width: double.infinity,
          child: calendar,
        );
      },
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    const labels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    return Row(
      children: labels
          .map(
            (label) => Expanded(
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.blueGrey.shade600,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.visibleMonth,
    required this.selectedDate,
    required this.sessions,
    required this.isWide,
    required this.onSelected,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final List<TeamSession> sessions;
  final bool isWide;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month);
    final gridStart = firstDay.subtract(
      Duration(days: firstDay.weekday - DateTime.monday),
    );
    final today = DateUtils.dateOnly(DateTime.now());

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 42,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: isWide ? 2.08 : 0.86,
        mainAxisSpacing: isWide ? 4 : 3,
        crossAxisSpacing: isWide ? 4 : 3,
      ),
      itemBuilder: (context, index) {
        final date = gridStart.add(Duration(days: index));
        final sessionCount = sessions
            .where((session) => DateUtils.isSameDay(session.startTime, date))
            .length;
        final selected = DateUtils.isSameDay(date, selectedDate);
        final isToday = DateUtils.isSameDay(date, today);
        final inVisibleMonth = date.month == visibleMonth.month;

        return Semantics(
          button: true,
          selected: selected,
          label:
              '${date.day} de ${formatSpanishMonth(date)}, '
              '$sessionCount sesiones',
          child: InkWell(
            key: ValueKey(
              'calendar-day-${date.year}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}',
            ),
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelected(DateUtils.dateOnly(date)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primary
                    : isToday
                    ? AppTheme.primary.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: isToday && !selected
                    ? Border.all(color: AppTheme.primary.withValues(alpha: 0.5))
                    : null,
              ),
              child: Column(
                children: [
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : inVisibleMonth
                          ? AppTheme.navy
                          : Colors.blueGrey.shade300,
                      fontWeight: selected || isToday
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (sessionCount > 0)
                    Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : AppTheme.accent,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$sessionCount',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected ? AppTheme.primary : AppTheme.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
