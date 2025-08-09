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
    swiftOut: 'ios/Classes/Uwb.g.swift',
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
  OOB_ERROR,
  OOB_DEVICE_ALREADY_CONNECTED,
  OOB_CONNECTION_ERROR,
  OOB_DEVICE_NOT_FOUND,
  OOB_ALREADY_ADVERTISING,
  OOB_ALREADY_DISCOVERING,
  OOB_SENDING_DATA_FAILED,
  UWB_ERROR,
  UWB_TOO_MANY_SESSIONS,
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

/// Direction for iOS
class Direction3D {
  /// The x component of the vector.
  final double x;

  /// The y component of the vector.
  final double y;

  /// The z component of the vector.
  final double z;

  Direction3D({required this.x, required this.y, required this.z});
}

/// UWB Data for Android and iOS
class UwbData {
  /// Android API: The line-of-sight distance in meters of the ranging device, or null if not available.
  /// Apple API: The distance from the user's device to the peer device in meters.
  final double? distance;

  /// Android API: The azimuth angle in degrees of the ranging device, or null if not available.
  final double? azimuth;

  /// Android API: The elevation angle in degrees of the ranging device, or null if not available.
  final double? elevation;

  /// Apple API: A vector that points from the user’s device in the direction of the peer device.
  /// If direction is null, the peer device is out of view.
  final Direction3D? direction;

  /// Apple API: An angle in radians that indicates the azimuthal direction to the nearby object.
  /// The framework sets a value of this property when cameraAssistanceEnabled is true.
  /// iOS: >= iOS 16.0
  final double? horizontalAngle;

  UwbData(
      {this.distance,
      this.azimuth,
      this.elevation,
      this.direction,
      this.horizontalAngle});
}

/// Represents a UWB device for Android and iOS.
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

@Dataclass()
class UwbSessionConfig {
  final int sessionId;
  final Uint8List? sessionKeyInfo;
  final int channel;
  final int preambleIndex;
}


// -------- Host API -------- //

@HostApi()
abstract class UwbHostApi {
  // OOB
  void discoverDevices(String deviceName);
  void stopDiscovery();
  void handleConnectionRequest(UwbDevice device, bool accept);
  bool isUwbSupported();

  // UWB
  void startRanging(UwbDevice device, UwbSessionConfig config);
  void stopRanging(UwbDevice device);
  void stopUwbSessions();
}

// -------- Flutter API -------- //

@FlutterApi()
abstract class UwbFlutterApi {
  // OOB
  void onDiscoveryDeviceConnected(UwbDevice device);
  void onDiscoveryDeviceDisconnected(UwbDevice device);
  void onDiscoveryDeviceFound(UwbDevice device);
  void onDiscoveryDeviceLost(UwbDevice device);
  void onDiscoveryDeviceRejected(UwbDevice device);
  void onDiscoveryConnectionRequestReceived(UwbDevice device);
  void onPermissionRequired(PermissionAction action);

  // UWB
  void onUwbSessionStarted(UwbDevice device);
  void onUwbSessionDisconnected(UwbDevice device);

  void _buildTrigger(ErrorCode code, DeviceState state);
}
