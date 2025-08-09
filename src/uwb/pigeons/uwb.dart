// ignore_for_file: public_member_api_docs

import 'package:pigeon/pigeon.dart';

// ############################################################################
// ############################## DATA OBJECTS ################################
// ############################################################################

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

/// Represents a UWB-capable device.
/// The name is discovered via the out-of-band BLE channel.
/// The rangingData is nullable because a device might be discovered via BLE
/// before UWB ranging has started.
class UwbDevice {
  final Uint8List address;
  final String name;
  final UwbRangingData? rangingData;

  UwbDevice({required this.address, required this.name, this.rangingData});
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

// ############################################################################
// ################################ HOST API ##################################
// ############################################################################

@HostApi()
abstract class UwbHostApi {
  @async
  Uint8List getLocalUwbAddress();

  bool isUwbSupported();

  // The isAccessory flag is crucial for cross-platform (iOS <-> Android) compatibility.
  void startRanging(
      Uint8List peerAddress, UwbSessionConfig config, bool isAccessory);

  void stopRanging(Uint8List peerAddress);

  void stopUwbSessions();
}

// ############################################################################
// ############################## FLUTTER API #################################
// ############################################################################

@FlutterApi()
abstract class UwbFlutterApi {
  // A single, rich stream of data for a specific device.
  void onRangingResult(UwbDevice device);
  void onRangingError(Object error);
  // This can be used to notify when a specific peer is no longer being ranged.
  void onPeerDisconnected(UwbDevice device);
}
