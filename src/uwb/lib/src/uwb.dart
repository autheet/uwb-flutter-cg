import 'dart:async';
import 'package:flutter/services.dart';
import 'package:uwb/src/uwb.g.dart';
import 'package:uwb/src/exceptions.dart';
import 'package:uwb/src/oob_ble.dart';

export 'package:uwb/src/uwb.g.dart' show UwbRangingDevice, UwbRangingData, UwbDeviceState;

/// The main class for interacting with the UWB plugin.
class FlutterUwb implements UwbFlutterApi {
  final _rangingResultController = StreamController<UwbRangingDevice>.broadcast();
  final _rangingErrorController = StreamController<String>.broadcast();

  final UwbHostApi _hostApi = UwbHostApi();
  late final OobBle _oobBle;

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

  // --- Public API ---

  /// A stream of UWB ranging results.
  Stream<UwbRangingDevice> get rangingResultStream =>
      _rangingResultController.stream;

  /// A stream of ranging errors.
  Stream<String> get rangingErrorStream =>
      _rangingErrorController.stream;

  /// Starts the UWB session.
  Future<void> start({
    required String deviceName,
    required String serviceUuid,
    required String handshakeCharacteristicUuid,
    required String platformCharacteristicUuid,
  }) async {
    _oobBle = OobBle(
      serviceUuid: serviceUuid,
      handshakeCharacteristicUuid: handshakeCharacteristicUuid,
      platformCharacteristicUuid: platformCharacteristicUuid,
      deviceName: deviceName,
    );
    await _oobBle.start();
  }

  /// Stops the UWB session.
  void stop() {
    _oobBle.dispose();
  }

  /// Disposes of the streams.
  void dispose() {
    _rangingResultController.close();
    _rangingErrorController.close();
    _oobBle.dispose();
  }

  UwbException _parsePlatformException(PlatformException e) {
    return UwbException(e.code, e.message);
  }
}
