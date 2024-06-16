import 'package:flutter/material.dart';

class MapObject {
  final String name;
  final Offset position;
  double distance;

  MapObject(this.name, this.position, this.distance);
}

class LocalisationMap extends CustomPainter {
  List<MapObject> tags = [];
  MapObject phone;

  LocalisationMap(this.tags, this.phone);
  final scale = 70.0;
  final Offset origin = const Offset(40, 40);

  @override
  void paint(Canvas canvas, Size size) {
    Paint circlePaint = Paint();
    circlePaint.color = Colors.black;
    circlePaint.style = PaintingStyle.fill;
    circlePaint.strokeCap = StrokeCap.round;
    circlePaint.strokeJoin = StrokeJoin.round;

    final gridLines = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1.0;

    final gridBoarder = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.0;

    final double boxSize = 20.0;
    final double width = size.width;
    final double height = size.height;

    // Horizontal lines
    for (double y = 0; y < height; y += boxSize) {
      canvas.drawLine(Offset(0, y), Offset(width, y), gridLines);

      if (y == 1) {
        canvas.drawLine(Offset(0, y), Offset(width, y), gridBoarder);
      }
    }

    // Vertical lines
    for (double x = 0; x < width; x += boxSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, height), gridLines);
    }

    canvas.drawLine(
        Offset(1, origin.dx), Offset(width, origin.dx), gridBoarder);

    canvas.drawLine(
        Offset(origin.dy, 1), Offset(origin.dy, height), gridBoarder);

    for (var tag in tags) {
      canvas.drawCircle(tag.position * scale + origin, 10, circlePaint);

      canvas.drawCircle(
        tag.position * scale + origin,
        tag.distance * scale,
        Paint()..color = Colors.blue.withOpacity(0.3),
      );

      final textStyle = TextStyle(color: Colors.black, fontSize: 14.0);
      final textPainter = TextPainter(
          textAlign: TextAlign.center, textDirection: TextDirection.ltr);

      textPainter.text = TextSpan(text: tag.name, style: textStyle);
      textPainter.layout();

      // Calculate text position to center it over the circle
      double textX =
          tag.position.dx * scale - textPainter.width / 2 + origin.dx;
      double textY =
          tag.position.dy * scale - 15 - textPainter.height + origin.dy;

      textPainter.paint(canvas, Offset(textX, textY));
    }

    circlePaint.color = Colors.red;
    canvas.drawCircle(phone.position * scale, 10, circlePaint);

    final textStyle = TextStyle(color: Colors.black, fontSize: 14.0);
    final textPainter = TextPainter(
        textAlign: TextAlign.center, textDirection: TextDirection.ltr);

    textPainter.text = TextSpan(
      text:
          "X: ${phone.position.dx.toStringAsFixed(3)} Y: ${phone.position.dy.toStringAsFixed(3)}",
      style: textStyle,
    );
    textPainter.layout();

    // Calculate text position to center it over the circle
    // set position bottom center
    double textX = phone.position.dx * scale - textPainter.width / 2;
    double textY = phone.position.dy * scale + 15;
    textPainter.paint(canvas, Offset(textX, textY));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
