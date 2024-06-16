import 'dart:math';
import 'dart:ui';

class TrialaterationPoint {
  final double x;
  final double y;
  double distance;

  TrialaterationPoint(this.x, this.y, this.distance);
}

Offset trilaterate(TrialaterationPoint point1, TrialaterationPoint point2,
    TrialaterationPoint point3) {
  var a = pow(point1.x, 2) + pow(point1.y, 2) - pow(point1.distance, 2);
  var b = pow(point2.x, 2) + pow(point2.y, 2) - pow(point2.distance, 2);
  var c = pow(point3.x, 2) + pow(point3.y, 2) - pow(point3.distance, 2);

  var x32 = point3.x - point2.x;
  var x13 = point1.x - point3.x;
  var x21 = point2.x - point1.x;
  var y32 = point3.y - point2.y;
  var y13 = point1.y - point3.y;
  var y21 = point2.y - point1.y;

  var x = (a * y32 + b * y13 + c * y21) /
      (2 * (point1.x * y32 + point2.x * y13 + point3.x * y21));
  var y = (a * x32 + b * x13 + c * x21) /
      (2 * (point1.y * x32 + point2.y * x13 + point3.y * x21));

  return Offset(x, y);
}
