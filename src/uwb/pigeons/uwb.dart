// ignore_for_file: constant_identifier_names

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/uwb.g.dart',
  dartOptions: DartOptions(),
  kotlinOut: 'android/src/main/kotlin/net/christiangreiner/uwb/Uwb.g.kt',
  kotlinOptions: KotlinOptions(),
  swiftOut: 'ios/Classes/Uwb.g.swift',
  swiftOptions: SwiftOptions(),
  dartPackageName: 'uwb',
))

/// A data class for passing ranging results from native to Dart.
class RangingResult {
  RangingResult({
    required this.address,
    required this.distance,
    required this.azimuth,
    required this.elevation,
  });

  final String address;
  final double distance;
  final double azimuth;
  final double elevation;
}

/// The API exposed by the native platform to be called from Dart.
@HostApi()
abstract class UwbHostApi {
  /// Stops any ongoing UWB session.
  @async
  void stopRanging();

  // --- Peer Ranging Methods (iOS <-> iOS) ---

  /// Retrieves the local device's NIDiscoveryToken for sharing. (iOS only)
  @async
  Uint8List getPeerDiscoveryToken();

  /// Starts a peer-to-peer ranging session. (iOS only)
  @async
  void startPeerRanging(Uint8List token);

  // --- Accessory Ranging Methods (iOS <-> Android / Android <-> Android) ---

  /// Retrieves the accessory's configuration data to be sent to a controller.
  @async
  Uint8List getAccessoryConfigurationData();

  /// Starts a ranging session as a Controller, using the accessory's data.
  /// Returns the shareable configuration data to be sent back to the accessory.
  @async
  Uint8List startControllerRanging(Uint8List accessoryData);

  /// Starts a ranging session as an Accessory, using the controller's shareable data.
  @async
  void startAccessoryRanging(Uint8List shareableData);
}

/// The API exposed by Dart to be called from the native platform.
@FlutterApi()
abstract class UwbFlutterApi {
  void onRangingResult(RangingResult result);
  void onRangingError(String error);
}
