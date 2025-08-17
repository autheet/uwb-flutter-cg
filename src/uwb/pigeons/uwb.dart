// ignore_for_file: public_member_api_docs

import 'package:pigeon/pigeon.dart';

// --- Data Classes ---
class RangingResult {
  RangingResult(this.peerAddress, this.deviceName, this.distance, this.azimuth, this.elevation);
  final String peerAddress;
  final String deviceName;
  final double? distance;
  final double? azimuth; // Horizontal angle
  final double? elevation; // Vertical angle
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

// --- API Definitions ---
@HostApi()
abstract class UwbHostApi {
  // --- Session Management ---
  @async
  void start(String deviceName, String serviceUUIDDigest);
  @async
  void stop();

  // --- iOS Peer-to-Peer Ranging (Apple devices only) ---
  // This uses NINearbyPeerConfiguration and is kept for iOS-iOS functionality.
  @async
  Uint8List startIosController();
  @async
  void startIosAccessory(Uint8List token);

  // --- FiRa Accessory Ranging (Cross-Platform) ---
  // Step 1: An accessory gets its own UWB address to share with a controller.
  @async
  Uint8List getAccessoryAddress();

  // Step 2: A controller takes an accessory's address and generates the full config for the session.
  @async
  UwbConfig generateControllerConfig(Uint8List accessoryAddress, Uint8List sessionKeyInfo, int sessionId);
  
  // Step 3: An accessory receives the full config from the controller and starts ranging.
  @async
  void startAccessoryRanging(UwbConfig config);
}

@FlutterApi()
abstract class UwbFlutterApi {
  void onRangingResult(RangingResult result);
  void onRangingError(String error);
  void onBleDataReceived(Uint8List data); 
  void onPeerDiscovered(String deviceName, String peerAddress);
  void onPeerLost(String deviceName, String peerAddress);
}
