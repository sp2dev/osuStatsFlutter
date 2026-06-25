import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Renders a mini line chart as a transparent PNG for home screen widgets.
/// No text or background is drawn — all text/background is handled by the
/// native Android layout. This keeps the chart crisp and avoids double-bg.
class WidgetChartRenderer {
  static Future<File> render({
    required int widgetId,
    required List<Map<String, dynamic>> dataPoints,
    required double widthDp,
    required double heightDp,
    ui.Color? lineColor,
  }) async {
    const pixelRatio = 3.0;
    final width = widthDp * pixelRatio;
    final height = heightDp * pixelRatio;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

    // Transparent background (Bug 7 fix: no opaque bg, let native layout handle it)

    final primaryColor = lineColor ?? const ui.Color(0xFFFF66AA);

    if (dataPoints.isNotEmpty) {
      // Values are already transformed by _extractDataPoints in WidgetDataService
      final values = dataPoints.map((dp) => (dp['value'] as num).toDouble()).toList();

      double minVal = values.reduce((a, b) => a < b ? a : b);
      double maxVal = values.reduce((a, b) => a > b ? a : b);

      if (minVal == maxVal) {
        minVal -= 1;
        maxVal += 1;
      } else {
        final diff = maxVal - minVal;
        minVal -= diff * 0.1;
        maxVal += diff * 0.1;
      }
      final range = maxVal - minVal;

      final padding = 6.0 * pixelRatio;
      final chartLeft = padding;
      final chartRight = width - padding;
      final chartTop = padding;
      final chartBottom = height - padding;
      final chartWidth = chartRight - chartLeft;
      final chartHeight = chartBottom - chartTop;

      final stepX = values.length > 1 ? chartWidth / (values.length - 1) : 0.0;

      // Build line path
      final path = Path();
      for (int i = 0; i < values.length; i++) {
        final x = chartLeft + i * stepX;
        final y = chartBottom - ((values[i] - minVal) / range) * chartHeight;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      // Fill below line
      final fillPath = Path.from(path);
      fillPath.lineTo(chartLeft + (values.length - 1) * stepX, chartBottom);
      fillPath.lineTo(chartLeft, chartBottom);
      fillPath.close();

      canvas.drawPath(
        fillPath,
        Paint()
          ..color = primaryColor.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
      );

      // Draw line
      canvas.drawPath(
        path,
        Paint()
          ..color = primaryColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * pixelRatio
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );

      // Draw dots
      final dotPaint = Paint()
        ..color = primaryColor
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      final dotBorderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      for (int i = 0; i < values.length; i++) {
        final x = chartLeft + i * stepX;
        final y = chartBottom - ((values[i] - minVal) / range) * chartHeight;
        canvas.drawCircle(Offset(x, y), 3.0 * pixelRatio, dotBorderPaint);
        canvas.drawCircle(Offset(x, y), 2.0 * pixelRatio, dotPaint);
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) {
      throw StateError('Failed to encode widget chart PNG');
    }
    final dir = await getApplicationCacheDirectory();
    final widgetDir = Directory('${dir.path}/widget_charts');
    if (!await widgetDir.exists()) {
      await widgetDir.create(recursive: true);
    }

    final file = File('${widgetDir.path}/widget_$widgetId.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file;
  }
}
