import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class BoundingBoxPainter extends CustomPainter {
  final List<Map<String, dynamic>> detections;
  final File image;

  BoundingBoxPainter(this.detections, this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final Map<String, Color> classColors = {
      'PIH': Colors.red,
      'PIE': Colors.orange,
      'Spot': Colors.purple,
    };

    for (var detection in detections) {
      final List<double> box = detection['box'];
      final String label = detection['label'];
      final double score = detection['score'];
      final Color boxColor = classColors[label] ?? Colors.red;

      final double imageAspectRatio =
          box[2] - box[0] > 0 && box[3] - box[1] > 0
              ? (box[2] - box[0]) / (box[3] - box[1])
              : 1.0;
      final double canvasAspectRatio = size.width / size.height;

      double scaleX, scaleY;
      double offsetX = 0, offsetY = 0;

      if (canvasAspectRatio > imageAspectRatio) {
        scaleY =
            size.height / (box[3] - box[1] > 0 ? box[3] - box[1] + box[1] : 1);
        scaleX = scaleY;
        offsetX = (size.width - (box[2] - box[0]) * scaleX) / 2;
      } else {
        scaleX =
            size.width / (box[2] - box[0] > 0 ? box[2] - box[0] + box[0] : 1);
        scaleY = scaleX;
        offsetY = (size.height - (box[3] - box[1]) * scaleY) / 2;
      }

      final boxPaint =
          Paint()
            ..color = boxColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0;

      final labelBgPaint =
          Paint()
            ..color = boxColor.withValues(alpha: 0.7)
            ..style = PaintingStyle.fill;

      final Rect rect = Rect.fromLTRB(
        box[0] * scaleX + offsetX,
        box[1] * scaleY + offsetY,
        box[2] * scaleX + offsetX,
        box[3] * scaleY + offsetY,
      );

      canvas.drawRect(rect, boxPaint);

      final textStyle = ui.TextStyle(color: Colors.white, fontSize: 14);

      final paragraphBuilder =
          ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.left))
            ..pushStyle(textStyle)
            ..addText('$label: ${(score * 100).toInt()}%');

      final paragraph =
          paragraphBuilder.build()..layout(ui.ParagraphConstraints(width: 150));

      canvas.drawRect(
        Rect.fromLTWH(
          rect.left,
          rect.top - paragraph.height - 2,
          paragraph.width + 8,
          paragraph.height + 2,
        ),
        labelBgPaint,
      );

      canvas.drawParagraph(
        paragraph,
        Offset(rect.left + 4, rect.top - paragraph.height - 2),
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
