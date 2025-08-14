import 'dart:async';
import 'package:flutter/services.dart';
import 'package:uwb/src/uwb.g.dart';

/// Public-facing API for the UWB plugin.
class FlutterUwb implements UwbFlutterApi {
  /// Singleton instance of the API.
  static final FlutterUwb _instance = FlutterUwb._internal();

  factory FlutterUwb() {
    return _instance;
  }

  FlutterUwb._internal() {
    // Set this class as the handler for native-to-Dart calls.
    UwbFlutterApi.setup(this);
  }

  /// The host API for calling native UWB functions.
  final UwbHostApi _hostApi = UwbHostApi();

  /// Stream controller for ranging results.
  final StreamController<RangingResult> _rangingResultController =
      StreamController.broadcast();

  /// Stream controller for ranging errors.
  final StreamController<String> _rangingErrorController =
      StreamController.broadcast();

  /// A stream of ranging results from the native UWB session.
  /// Listen to this stream to get distance and angle updates for a peer.
  Stream<RangingResult> get rangingResultsStream =>
      _rangingResultController.stream;

  /// A stream of errors from the native UWB session.
  Stream<String> get rangingErrorStream =>
      _rangingErrorController.stream;

  /// Called by the device acting as a Controller.
  /// Takes the configuration data from an accessory, initializes the native session,
  /// and returns the shareable configuration data to be sent back to the accessory.
  Future<Uint8List> initializeController(Uint8List accessoryConfigurationData) {
    return _hostApi.initializeController(accessoryConfigurationData);
  }

  /// Called by the device acting as an Accessory.
  /// Returns its own configuration data to be sent to the Controller.
  Future<Uint8List> getAccessoryConfigurationData() {
    return _hostApi.getAccessoryConfigurationData();
  }

  /// Starts the UWB ranging session after the OOB handshake is complete.
  ///
  /// [configData]: The final configuration data (the Shareable Config Data from the Controller).
  /// [isController]: Must be `true` if this device is the Controller, `false` if it's the Accessory.
  Future<void> startRanging(Uint8List configData, {required bool isController}) {
    return _hostApi.startRanging(configData, isController);
  }

  /// Stops the current UWB ranging session.
  Future<void> stopRanging() {
    return _hostApi.stopRanging();
  }

  // --- Callback handlers for UwbFlutterApi ---

  @override
  void onRangingResult(RangingResult result) {
    _rangingResultController.add(result);
  }

  @override
  void onRangingError(String error) {
    _rangingErrorController.add(error);
  }

  /// Disposes of the stream controllers.
  void dispose() {
    _rangingResultController.close();
    _rangingErrorController.close();
  }
}
