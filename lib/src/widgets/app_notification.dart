import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppNotificationType { success, error, warning, info }

void showAppNotification(
  BuildContext context, {
  required String message,
  AppNotificationType type = AppNotificationType.info,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: AppNotification(
          message: message,
          type: type,
          onDismiss: messenger.hideCurrentSnackBar,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: EdgeInsets.zero,
        duration: duration,
        dismissDirection: DismissDirection.horizontal,
      ),
    );
}

class AppNotification extends StatelessWidget {
  const AppNotification({
    required this.message,
    required this.type,
    this.onDismiss,
    super.key,
  });

  final String message;
  final AppNotificationType type;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final style = _NotificationStyle.forType(type);
    return Semantics(
      liveRegion: true,
      container: true,
      label: '${style.semanticLabel}: $message',
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: style.backgroundColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: style.foregroundColor.withValues(alpha: 0.2),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24102A43),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: style.foregroundColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(style.icon, color: style.foregroundColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: style.foregroundColor,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                key: const ValueKey('app-notification-close'),
                tooltip: 'Cerrar notificación',
                onPressed: onDismiss,
                icon: Icon(
                  Icons.close_rounded,
                  color: style.foregroundColor,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotificationStyle {
  const _NotificationStyle({
    required this.foregroundColor,
    required this.backgroundColor,
    required this.icon,
    required this.semanticLabel,
  });

  final Color foregroundColor;
  final Color backgroundColor;
  final IconData icon;
  final String semanticLabel;

  factory _NotificationStyle.forType(AppNotificationType type) {
    return switch (type) {
      AppNotificationType.success => const _NotificationStyle(
        foregroundColor: AppTheme.primary,
        backgroundColor: Color(0xFFE8F5F1),
        icon: Icons.check_circle_outline_rounded,
        semanticLabel: 'Operación completada',
      ),
      AppNotificationType.error => const _NotificationStyle(
        foregroundColor: Color(0xFFB42318),
        backgroundColor: Color(0xFFFFECEB),
        icon: Icons.error_outline_rounded,
        semanticLabel: 'Error',
      ),
      AppNotificationType.warning => const _NotificationStyle(
        foregroundColor: Color(0xFF8A5A00),
        backgroundColor: Color(0xFFFFF4D6),
        icon: Icons.warning_amber_rounded,
        semanticLabel: 'Atención',
      ),
      AppNotificationType.info => const _NotificationStyle(
        foregroundColor: AppTheme.navy,
        backgroundColor: Color(0xFFEAF2F8),
        icon: Icons.info_outline_rounded,
        semanticLabel: 'Información',
      ),
    };
  }
}
