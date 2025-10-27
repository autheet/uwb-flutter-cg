import 'dart:ui';

import 'package:rxdart/rxdart.dart';
import 'package:uwb/flutter_uwb.dart';

BehaviorSubject<Iterable<UwbDevice>> uwbDataStream = BehaviorSubject();

Map<String, Offset> uwbPositionMap = {
  'DWM3001CDK (9F186F02)': const Offset(0, 0),
  'DWM3001CDK (A7C68221)': const Offset(0, 5.14),
  'DWM3001CDK (4330CC40)': const Offset(4.5, 3.7),
};
