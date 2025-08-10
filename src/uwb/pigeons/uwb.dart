// ignore_for_file: public_member_api_docs

import 'package:pigeon/pigeon.dart';

// Pigeon Configuration
@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/uwb.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/net/christiangreiner/uwb/Uwb.g.kt',
    kotlinOptions: KotlinOptions(),
    swiftOut: 'ios/Classes/Uwb.g.swift', // CORRECTED path
    swiftOptions: SwiftOptions(),
    dartPackageName: 'uwb',
  ),
)

// -------- Data Models -------- //

enum DeviceType {
  smartphone,
  accessory,
}

enum ErrorCode {
  uwbError,
  uwbTooManySessions,
}

enum PermissionAction {
  request,
  restart,
}

enum DeviceState {
  connected,
  disconnected,
  found,
  lost,
  rejected,
  pending,
  ranging,
}

class Direction3D {
  final double x;
  final double y;
  final double z;

  Direction3D({required this.x, required this.y, required this.z});
}

class UwbData {
  final double? distance;
  final double? azimuth;
  final double? elevation;
  final Direction3D? direction;
  final double? horizontalAngle;

  UwbData(
      {this.distance,
      this.azimuth,
      this.elevation,
      this.direction,
      this.horizontalAngle});
}

class UwbDevice {
  final String id;
  final String name;
  final UwbData? uwbData;
  final DeviceType deviceType;
  final DeviceState? state;

  UwbDevice(
      {required this.id,
      required this.name,
      this.uwbData,
      required this.deviceType,
      this.state});
}

class UwbSessionConfig {
  final int sessionId;
  final Uint8List? sessionKeyInfo;
  final int channel;
  final int preambleIndex;

  UwbSessionConfig({
    required this.sessionId,
    this.sessionKeyInfo,
    required this.channel,
    required this.preambleIndex,
  });
}


// -------- Host API -------- //

@HostApi()
abstract class UwbHostApi {
  @async
  Uint8List getLocalUwbAddress();

  bool isUwbSupported();

  void startRanging(Uint8List peerAddress, UwbSessionConfig config);
  
  void stopRanging(String peerAddress);

  void stopUwbSessions();
}

// -------- Flutter API -------- //

@FlutterApi()
abstract class UwbFlutterApi {
  void onShareableConfigurationData(Uint8List data, String peerId);
  void onRanging(UwbDevice device);
  void onUwbSessionStarted(UwbDevice device);
  void onUwbSessionDisconnected(UwbDevice device);
  void onPermissionRequired(PermissionAction action);
}
