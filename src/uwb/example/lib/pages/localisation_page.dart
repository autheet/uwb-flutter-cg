import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uwb/flutter_uwb.dart';
import 'package:uwb_example/localisation/localisation_map.dart';
import 'package:uwb_example/math.dart';
import 'package:uwb_example/settings.dart';

class LocalisationPage extends StatefulWidget {
  final Uwb uwbPlugin;
  final String deviceName;

  const LocalisationPage({
    super.key,
    required this.uwbPlugin,
    required this.deviceName,
  });
  @override
  State<LocalisationPage> createState() => _LocalisationPage();
}

class _LocalisationPage extends State<LocalisationPage> {
  MapObject _phone = MapObject('Phone', const Offset(0, 0), 0);

  final StreamController<MapObject> _uwbPositionStream =
      StreamController.broadcast();

  Map<String, MapObject> uwbDevices = {};
  Map<String, double> avgDistance = {};
  Map<String, List<double>> deviceDistanceCache = {};
  int samplingSize = 10;

  @override
  void initState() {
    super.initState();

    uwbDataStream.listen(
      (devices) {
        for (var element in devices) {
          // check if valid uwb devices
          if (uwbPositionMap.containsKey(element.name)) {
            // UWBDevices is set by listen method
            if (uwbDevices.containsKey(element.name)) {
              // Update distance object
              var distance = element.uwbData?.distance ?? 0.0;
              uwbDevices[element.name]?.distance = distance;

              if (deviceDistanceCache.containsKey(element.name)) {
                deviceDistanceCache[element.name]!.add(distance);

                // add distance to cache
                if (deviceDistanceCache[element.name]!.length >= samplingSize) {
                  var mean = median(deviceDistanceCache[element.name]!);
                  avgDistance[element.name] = mean;
                  deviceDistanceCache[element.name] = [];
                }
              } else {
                //print('Device ${element.name} not found in cache');
              }
            }
          }
        }

        if (uwbDevices.length == 3) {
          var points = uwbDevices.values
              .where((element) => avgDistance.containsKey(element.name))
              .where((element) => avgDistance.length == 3)
              .map(
                (e) => TrialaterationPoint(
                  e.position.dx,
                  e.position.dy,
                  avgDistance[e.name]!,
                ),
              )
              /*.map((e) => TrialaterationPoint(
                    e.position.dx,
                    e.position.dy,
                    e.distance,
                  ))*/
              .toList();

          if (points.length == 3) {
            var phonePosition = trilaterate(points[0], points[1], points[2]);
            _phone = MapObject('Phone', phonePosition, 0);
            _uwbPositionStream.add(_phone);
          }
        }
      },
    );

    widget.uwbPlugin.uwbSessionStateStream.listen(
      (event) {
        switch (event) {
          case UwbSessionStartedState(device: var device):
            setState(
              () {
                if (uwbPositionMap.containsKey(device.name)) {
                  uwbDevices[device.name] = MapObject(
                    device.name,
                    uwbPositionMap[device.name]!,
                    device.uwbData?.distance ?? 0.0,
                  );

                  deviceDistanceCache[device.name] = [];
                  avgDistance[device.name] = 0.0;
                }
              },
            );
            break;
          case UwbSessionDisconnectedState(device: var device):
            setState(() {
              uwbDevices.remove(device.name);
            });
            break;
        }
      },
    );
  }

  @override
  void dispose() async {
    super.dispose();
    _uwbPositionStream.close();
  }

  double median(List<double> list) {
    if (list.isEmpty) {
      return 0.0;
    }

    if (list.length == 1) {
      return list[0];
    }

    list.sort();
    var middle = list.length ~/ 2;
    if (list.length % 2 == 1) {
      return list[middle];
    } else {
      return (list[middle - 1] + list[middle]) / 2.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Builder(
        builder: (context) {
          if (uwbDevices.length < 3) {
            return const Center(
              child: Text(
                'Please connect 3 UWB devices',
                style: TextStyle(fontSize: 24),
              ),
            );
          }

          return ClipRRect(
            child: StreamBuilder<MapObject>(
              stream: _uwbPositionStream.stream,
              builder: (context, snapshot) {
                return CustomPaint(
                  painter: LocalisationMap(
                    uwbDevices.values.toList(),
                    _phone,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
