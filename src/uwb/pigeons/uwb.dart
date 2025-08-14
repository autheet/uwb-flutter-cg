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

// --- API Definitions ---
@HostApi()
abstract class UwbHostApi {
  @async
  void start(String deviceName, String serviceUUIDDigest);

  @async
  void stop();

  // --- iOS Specific Methods ---
  @async
  Uint8List startIosController();

  @async
  void startIosAccessory(Uint8List token);

  // --- Android Specific Methods ---
  @async
  Uint8List getAndroidAccessoryConfigurationData();

  @async
  Uint8List initializeAndroidController(Uint8List accessoryConfigurationData);

  @async
  void startAndroidRanging(Uint8List configData, bool isController);
}

@FlutterApi()
abstract class UwbFlutterApi {
  void onRangingResult(RangingResult result);
  void onRangingError(String error);
  void onBleDataReceived(Uint8List data); 
  void onPeerDiscovered(String deviceName, String peerAddress);
  void onPeerLost(String deviceName, String peerAddress);
}
