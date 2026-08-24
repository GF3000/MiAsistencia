import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum SessionViewMode { list, calendar, players }

class SessionViewSwitcher extends StatelessWidget {
  const SessionViewSwitcher({
    required this.value,
    required this.onChanged,
    this.showPlayers = false,
    super.key,
  });

  final SessionViewMode value;
  final ValueChanged<SessionViewMode> onChanged;
  final bool showPlayers;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE5E8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            Expanded(
              child: _ViewOption(
                key: const ValueKey('session-view-list'),
                label: 'Lista',
                icon: Icons.view_agenda_outlined,
                selected: value == SessionViewMode.list,
                compact: showPlayers,
                onTap: () => onChanged(SessionViewMode.list),
              ),
            ),
            Expanded(
              child: _ViewOption(
                key: const ValueKey('session-view-calendar'),
                label: 'Calendario',
                icon: Icons.calendar_month_outlined,
                selected: value == SessionViewMode.calendar,
                compact: showPlayers,
                onTap: () => onChanged(SessionViewMode.calendar),
              ),
            ),
            if (showPlayers)
              Expanded(
                child: _ViewOption(
                  key: const ValueKey('session-view-players'),
                  label: 'Jugadores',
                  icon: Icons.groups_2_outlined,
                  selected: value == SessionViewMode.players,
                  compact: true,
                  onTap: () => onChanged(SessionViewMode.players),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ViewOption extends StatelessWidget {
  const _ViewOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.compact,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = selected ? Colors.white : AppTheme.navy;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Vista $label',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: selected ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 12,
              vertical: 13,
            ),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x24102A43),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: foregroundColor),
                SizedBox(width: compact ? 6 : 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foregroundColor,
                      fontWeight: FontWeight.w800,
                      fontSize: compact ? 13 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
