import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../models/attendance.dart';
import '../theme/app_theme.dart';

typedef PlayerAttendanceImageRow = ({
  String playerName,
  PlayerAttendanceStats stats,
});

/// A column of the shareable player table: its heading, value and color.
typedef _ImageColumn = ({
  String label,
  int Function(PlayerAttendanceStats stats) value,
  Color color,
});

final List<_ImageColumn> _columns = [
  (
    label: 'Pista',
    value: (stats) => stats.courtCount,
    color: const Color(0xFF2563A5),
  ),
  (
    label: 'Físico',
    value: (stats) => stats.physicalCount,
    color: const Color(0xFF7650A8),
  ),
  (label: 'Partidos', value: (stats) => stats.matchCount, color: AppTheme.navy),
  (
    label: 'Desconvocados',
    value: (stats) => stats.uncalledMatchCount,
    color: const Color(0xFF475569),
  ),
];

const double _padding = 32;
const double _nameWidth = 300;
const double _columnWidth = 140;
const double _headerHeight = 44;
const double _rowHeight = 40;
const double _pixelRatio = 2;

/// Renders the shareable player table (court, physical, matches and
/// matches not called up) as a PNG, in the order of [rows].
Future<Uint8List> buildPlayerAttendanceImage({
  required String title,
  required String subtitle,
  required List<PlayerAttendanceImageRow> rows,
}) async {
  final tableWidth = _nameWidth + _columns.length * _columnWidth;
  final width = tableWidth + _padding * 2;
  final tableTop = _padding + 70;
  final height = tableTop + _headerHeight + rows.length * _rowHeight + 56;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(_pixelRatio);

  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  _drawText(
    canvas,
    title,
    const Offset(_padding, _padding),
    const TextStyle(
      color: AppTheme.navy,
      fontSize: 26,
      fontWeight: FontWeight.w800,
    ),
  );
  _drawText(
    canvas,
    subtitle,
    const Offset(_padding, _padding + 38),
    const TextStyle(color: Color(0xFF52606D), fontSize: 15),
  );

  canvas.drawRect(
    Rect.fromLTWH(_padding, tableTop, tableWidth, _headerHeight),
    Paint()..color = AppTheme.primary.withValues(alpha: 0.08),
  );
  const headerStyle = TextStyle(
    color: AppTheme.navy,
    fontSize: 14,
    fontWeight: FontWeight.w800,
  );
  _drawCell(
    canvas,
    'Jugador',
    left: _padding + 14,
    top: tableTop,
    width: _nameWidth - 14,
    height: _headerHeight,
    style: headerStyle,
  );
  for (var index = 0; index < _columns.length; index++) {
    _drawCell(
      canvas,
      _columns[index].label,
      left: _padding + _nameWidth + index * _columnWidth,
      top: tableTop,
      width: _columnWidth - 14,
      height: _headerHeight,
      style: headerStyle,
      alignRight: true,
    );
  }

  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    final top = tableTop + _headerHeight + rowIndex * _rowHeight;
    if (rowIndex.isOdd) {
      canvas.drawRect(
        Rect.fromLTWH(_padding, top, tableWidth, _rowHeight),
        Paint()..color = const Color(0xFFF5F7FA),
      );
    }
    _drawCell(
      canvas,
      row.playerName,
      left: _padding + 14,
      top: top,
      width: _nameWidth - 14,
      height: _rowHeight,
      style: const TextStyle(
        color: AppTheme.navy,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
    for (var index = 0; index < _columns.length; index++) {
      final column = _columns[index];
      _drawCell(
        canvas,
        '${column.value(row.stats)}',
        left: _padding + _nameWidth + index * _columnWidth,
        top: top,
        width: _columnWidth - 14,
        height: _rowHeight,
        style: TextStyle(
          color: column.color,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
        alignRight: true,
      );
    }
  }

  final tableBottom = tableTop + _headerHeight + rows.length * _rowHeight;
  canvas.drawLine(
    Offset(_padding, tableBottom),
    Offset(_padding + tableWidth, tableBottom),
    Paint()
      ..color = const Color(0xFFD8E1E8)
      ..strokeWidth = 1,
  );
  _drawText(
    canvas,
    'Pista y Físico: entrenamientos (incluye retrasos). '
    'Partidos: partidos a los que asistió. '
    'Desconvocados: no convocado.',
    Offset(_padding, tableBottom + 16),
    const TextStyle(color: Color(0xFF7B8794), fontSize: 12),
    maxWidth: tableWidth,
  );

  final image = await recorder.endRecording().toImage(
    (width * _pixelRatio).ceil(),
    (height * _pixelRatio).ceil(),
  );
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void _drawText(
  Canvas canvas,
  String text,
  Offset offset,
  TextStyle style, {
  double? maxWidth,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth ?? double.infinity);
  painter.paint(canvas, offset);
  painter.dispose();
}

void _drawCell(
  Canvas canvas,
  String text, {
  required double left,
  required double top,
  required double width,
  required double height,
  required TextStyle style,
  bool alignRight = false,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: width);
  final dx = alignRight ? left + width - painter.width : left;
  painter.paint(canvas, Offset(dx, top + (height - painter.height) / 2));
  painter.dispose();
}
