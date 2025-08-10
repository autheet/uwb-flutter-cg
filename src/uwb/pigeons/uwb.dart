// ignore_for_file: public_member_api_docs

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/uwb.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/src/main/kotlin/net/christiangreiner/uwb/Uwb.g.kt',
    kotlinOptions: KotlinOptions(
      errorClassName: 'UwbError',
      package: 'net.christiangreiner.uwb',
    ),
    swiftOut: 'ios/Classes/Uwb.g.swift',
    swiftOptions: SwiftOptions(),
  ),
)

// -------- Data Models -------- //

enum UwbDeviceState {
  connected,
  disconnected,
  ranging,
  lost,
}

class UwbRangingData {
  final double? distance;
  final double? azimuth;
  final double? elevation;

  UwbRangingData({
    this.distance,
    this.azimuth,
    this.elevation,
  });
}

class UwbRangingDevice {
  final String id;
  final UwbDeviceState state;
  final UwbRangingData? data;

  UwbRangingDevice({
    required this.id,
    required this.state,
    this.data,
  });
}

// -------- Host API (called from Dart) -------- //

@HostApi()
abstract class UwbHostApi {
  @async
  bool isSupported();

  @async
  Uint8List getLocalEndpoint();

  @async
  void startRanging(Uint8List peerEndpoint, bool isController);

  @async
  void stopRanging();

  @async
  void closeSession();
}

// -------- Flutter API (called from native) -------- //

@FlutterApi()
abstract class UwbFlutterApi {
  void onRangingResult(UwbRangingDevice device);
  void onRangingError(String error);
}
