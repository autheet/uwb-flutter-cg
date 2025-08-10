import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uwb/src/uwb.g.dart';
import 'package:uwb/src/exceptions.dart';
import 'package:uwb/src/states.dart';
import 'package:uwb/src/oob_ble.dart';
export 'package:uwb/src/uwb.g.dart' show UwbConfig;

// UWB Instance for Plugin
class Uwb implements UwbFlutterApi {
  final _uwbSessionStateStream = StreamController<UwbSessionState>.broadcast();
  final _uwbDataStreamController = StreamController<List<UwbDevice>>.broadcast();
  final _permissionRequestController = StreamController<PermissionAction>.broadcast();
  final _rangingDevices = <String, UwbDevice>{};
  OobBle? _oobBle;
  CentralManager? _centralManager;
  PeripheralManager? _peripheralManager;

  final UwbHostApi _hostApi = UwbHostApi();

  static final Uwb _instance = Uwb._internal();
  factory Uwb() => _instance;

  Uwb._internal();

  // --- FlutterApi Implementation (Internal) ---

  @override
  void onRanging(UwbDevice device) {
    _rangingDevices[device.id] = device;
    if (!_uwbDataStreamController.isClosed) {
      _uwbDataStreamController.add(_rangingDevices.values.toList());
    }
  }
  
  @override
  void onUwbSessionStarted(UwbDevice device) {
    _rangingDevices[device.id] = device;
    _uwbSessionStateStream.add(UwbSessionStartedState(device));
  }

  @override
  void onUwbSessionDisconnected(UwbDevice device) {
    _rangingDevices.remove(device.id);
    _uwbSessionStateStream.add(UwbSessionDisconnectedState(device));
  }
  
  @override
  void onPermissionRequired(PermissionAction action) {
    if (!_permissionRequestController.isClosed) {
      _permissionRequestController.add(action);
    }
  }

  @override
  void onShareableConfigurationData(Uint8List data, String peerId) {
    _oobBle?.sendShareableConfig(peerId: peerId, data: data);
  }

  // --- Public API ---

  Stream<UwbSessionState> get uwbSessionStateStream =>
      _uwbSessionStateStream.stream;

  Stream<List<UwbDevice>> get uwbDataStream =>
      _uwbDataStreamController.stream;
      
  Stream<PermissionAction> get permissionRequestStream =>
      _permissionRequestController.stream;

  Future<void> start({
    String? deviceName,
    required String serviceUuid,
    required String handshakeCharacteristicUuid,
    required String platformCharacteristicUuid,
    UwbConfig? config,
  }) async {
    if (_oobBle != null) {
      debugPrint("UWB session already active. Please stop the current session before starting a new one.");
      return;
    }
    
    _centralManager = CentralManager();
    _peripheralManager = PeripheralManager();

    final sessionConfig = config ?? UwbConfig(
      sessionId: 1234,
      sessionKeyInfo: null,
      channel: 9,
      preambleIndex: 10,
    );

    _oobBle = OobBle(
      this,
      _centralManager!,
      _peripheralManager!,
      UUID.fromString(serviceUuid),
      UUID.fromString(handshakeCharacteristicUuid),
      UUID.fromString(platformCharacteristicUuid),
      sessionConfig,
      deviceName: deviceName,
    );
    await _oobBle!.start();
  }
  
  void stop() {
    _oobBle?.dispose();
    _oobBle = null;
    _centralManager = null;
    _peripheralManager = null;
    stopUwbSessions();
  }

  Future<void> stopRanging(String peerAddress) async {
    try {
      await _hostApi.stopRanging(peerAddress);
    } on PlatformException catch (e) {
      _parsePlatformException(e);
    }
  }

  Future<void> stopUwbSessions() async {
    try {
      _rangingDevices.clear();
      return await _hostApi.stopUwbSessions();
    } on PlatformException catch (e) {
      _parsePlatformException(e);
    }
  }

  Future<bool> isUwbSupported() async {
    return await _hostApi.isUwbSupported();
  }

  // --- Internal Methods (called by OobBle) ---

  void startControllerSession(UwbConfig config) async {
    try {
      await _hostApi.startControllerSession(config);
    } on PlatformException catch (e) {
      _parsePlatformException(e);
    }
  }

  void startAccessorySession(UwbConfig config) async {
    try {
      await _hostApi.startAccessorySession(config);
    } on PlatformException catch (e) {
      _parsePlatformException(e);
    }
  }

  void startPeerSession(Uint8List peerToken, UwbConfig config) async {
    try {
      await _hostApi.startPeerSession(peerToken, config);
    } on PlatformException catch (e) {
      _parsePlatformException(e);
    }
  }

  Future<Uint8List> getLocalUwbAddress() async {
    return await _hostApi.getLocalUwbAddress();
  }

  void dispose() {
    _uwbSessionStateStream.close();
    _uwbDataStreamController.close();
    _permissionRequestController.close();
  }

  void _parsePlatformException(PlatformException e) {
    final code = int.tryParse(e.code);
    if(code != null && code < ErrorCode.values.length) {
      throw UwbException(ErrorCode.values[code], e.message);
    }
  }
}
