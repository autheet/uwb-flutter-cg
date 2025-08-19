// ignore_for_file: constant_identifier_names

import 'package:pigeon/pigeon.dart';

// #docregion config
@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/uwb_native_int.g.dart',
  dartOptions: DartOptions(),
  kotlinOut: 'android/src/main/kotlin/net/christiangreiner/uwb/UwbNativeInt.g.kt',
  kotlinOptions: KotlinOptions(),
  swiftOut: 'ios/Classes/UwbNativeInt.g.swift',
  swiftOptions: SwiftOptions(),
  dartPackageName: 'uwb',
))
// #enddocregion config

// #docregion host-definitions

/// Direction for iOS
class Direction3D {
  Direction3D({
    required this.x,
    required this.y,
    required this.z,
  });

  /// The x component of the vector.
  double x;

  /// The y component of the vector.
  double y;

  /// The z component of the vector.
  double z;
}

/// UWB Data for Android and iOS
// FOrce to generate class
class UwbData {
  /// Android API: The line-of-sight distance in meters of the ranging device, or null if not available.
  /// Apple API: The distance from the user's device to the peer device in meters.
  double? distance;

  /// Android API: The azimuth angle in degrees of the ranging device, or null if not available.
  double? azimuth;

  /// Android API: The elevation angle in degrees of the ranging device, or null if not available.
  double? elevation;

  /// Apple API: A vector that points from the user’s device in the direction of the peer device.
  /// If direction is null, the peer device is out of view.
  Direction3D? direction;

  /// Apple API: An angle in radians that indicates the azimuthal direction to the nearby object.
  /// The framework sets a value of this property when cameraAssistanceEnabled is true.
  /// iOS: >= iOS 16.0
  double? horizontalAngle;
}


/// A data class to hold all necessary UWB configuration parameters for the
/// FiRa accessory protocol. This ensures that both the controller and accessory
/// are using the exact same settings for the ranging session.
class UwbConfig {
  /// Corresponds to RangingParameters.UwbConfigId (e.g., CONFIG_UNICAST_DS_TWR).
  final int uwbConfigId;
  /// The session ID for the ranging interaction.
  final int sessionId;
  /// The session key for securing the ranging data.
  final Uint8List sessionKeyInfo;
  /// The UWB channel to be used.
  final int channel;
  /// The preamble index for the UWB signal.
  final int preambleIndex;
  /// The UWB address of the peer device (the one not generating this config).
  final Uint8List peerAddress;

  UwbConfig({
    required this.uwbConfigId,
    required this.sessionId,
    required this.sessionKeyInfo,
    required this.channel,
    required this.preambleIndex,
    required this.peerAddress,
  });
}

enum DeviceType { iosdevice, accessory, controller, controllee }

/// Represents a UWB device for Android and iOS.
class UwbDevice {
  UwbDevice({
    required this.id,
    required this.name,
    required this.deviceType,
    required this.state,
  });

  // The unique ID of the device.
  // Android: Endpoint ID of the Nearby Connection API
  // iOS: MCPeerID of the MultipeerConnectivity framework (display name of the peer)
  String id;

  // The display name of the device.
  String name;

  // The uwb data of the device.
  UwbData? uwbData;

  // The type of the device.
  DeviceType deviceType;

  // The state of the device.
  DeviceState? state;

  // The RSSI value of the device during discovery.
  int? rssi;
}

enum ErrorCode {

  UWB_ERROR,
  UWB_TOO_MANY_SESSIONS,
}

enum PermissionAction { request, restart }

enum DeviceState {
  connected,
  disconnected,
  found,
  lost,
  rejected,
  pending,
  ranging
}

@HostApi()
abstract class UwbHostApi {


  @async
  void handleConnectionRequest(UwbDevice device, bool accept);
  @async

  @async
  bool isUwbSupported();

  @async
  void startRanging(UwbDevice device);

 @async
  void discoverDevices(String deviceName, String auHourlyDigest);

  @async
  void stopRanging(UwbDevice device);

  @async
  void stopUwbSessions();
}
// #enddocregion host-definitions

// #docregion flutter-definitions
@FlutterApi()
abstract class UwbFlutterApi {
  void onHostDiscoveryDeviceConnected(UwbDevice device);
  void onHostDiscoveryDeviceDisconnected(UwbDevice device);
  void onHostDiscoveryDeviceFound(UwbDevice device);
  void onHostDiscoveryDeviceLost(UwbDevice device);
  void onHostDiscoveryDeviceRejected(UwbDevice device);
  void onHostDiscoveryConnectionRequestReceived(UwbDevice device);

  void onHostPermissionRequired(PermissionAction action);

  void onHostUwbSessionStarted(UwbDevice device);
  void onHostUwbSessionDisconnected(UwbDevice device);

  void onUwbRangingResult(UwbData data);
  void onUwbRangingError(String error);

  // This method is only for building enums in the generated file
  void _buildTrigger(ErrorCode code, DeviceState state);
}
// #enddocregion flutter-definitions
