import 'dart:async';
import 'package:flutter/services.dart';
import 'package:uwb/src/uwb.g.dart';
import 'package:uwb/src/exceptions.dart';

export 'package:uwb/src/uwb.g.dart' show UwbRangingDevice, UwbRangingData, UwbDeviceState;

/// The main class for interacting with the UWB plugin.
class FlutterUwb implements UwbFlutterApi {
  final _rangingResultController = StreamController<UwbRangingDevice>.broadcast();
  final _rangingErrorController = StreamController<String>.broadcast();
  final _shareableConfigController = StreamController<Uint8List>.broadcast();

  final UwbHostApi _hostApi = UwbHostApi();

  static final FlutterUwb _instance = FlutterUwb._internal();
  factory FlutterUwb() => _instance;

  FlutterUwb._internal() {
    UwbFlutterApi.setup(this);
  }

  // --- FlutterApi Implementation (Internal) ---

  @override
  void onRangingResult(UwbRangingDevice device) {
    if (!_rangingResultController.isClosed) {
      _rangingResultController.add(device);
    }
  }

  @override
  void onRangingError(String error) {
    if (!_rangingErrorController.isClosed) {
      _rangingErrorController.add(error);
    }
  }

  @override
  void onShareableConfigurationData(Uint8List data, String peerId) {
    if (!_shareableConfigController.isClosed) {
      _shareableConfigController.add(data);
    }
  }

  // --- Public API ---

  /// A stream of UWB ranging results.
  Stream<UwbRangingDevice> get rangingResultStream =>
      _rangingResultController.stream;

  /// A stream of ranging errors.
  Stream<String> get rangingErrorStream =>
      _rangingErrorController.stream;

  /// A stream of shareable configuration data (for iOS).
  Stream<Uint8List> get shareableConfigStream =>
      _shareableConfigController.stream;

  /// Checks if UWB is supported on the device.
  Future<bool> isSupported() async {
    return await _hostApi.isSupported();
  }

  /// Gets the local UWB endpoint identifier.
  Future<Uint8List> getLocalEndpoint() async {
    return await _hostApi.getLocalEndpoint();
  }

  /// Starts a ranging session with a peer.
  Future<void> startRanging(Uint8List peerEndpoint, {bool isController = false}) async {
    try {
      await _hostApi.startRanging(peerEndpoint, isController);
    } on PlatformException catch (e) {
      throw _parsePlatformException(e);
    }
  }

  /// Stops the current ranging session.
  Future<void> stopRanging() async {
    try {
      await _hostApi.stopRanging();
    } on PlatformException catch (e) {
      throw _parsePlatformException(e);
    }
  }

  /// Closes the UWB session and releases all resources.
  Future<void> closeSession() async {
    try {
      await _hostApi.closeSession();
    } on PlatformException catch (e) {
      throw _parsePlatformException(e);
    }
  }

  /// Disposes of the streams.
  void dispose() {
    _rangingResultController.close();
    _rangingErrorController.close();
    _shareableConfigController.close();
  }

  UwbException _parsePlatformException(PlatformException e) {
    return UwbException(e.code, e.message);
  }
}
