import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uwb/src/uwb.g.dart';
import 'package:uwb/src/uwb_platform_interface.dart';
import 'package:uwb/src/exceptions.dart';
import 'package:uwb/src/states.dart';
import 'package:uwb/src/oob_ble.dart';

// UWB Instance for Plugin
class Uwb extends UwbPlatform implements UwbFlutterApi {
  final _uwbSessionStateStream = StreamController<UwbSessionState>.broadcast();
  final _uwbDataStreamController = StreamController<List<UwbDevice>>.broadcast();
  final _permissionRequestController = StreamController<PermissionAction>.broadcast();
  final _rangingDevices = <String, UwbDevice>{};
  OobBle? _oobBle;
  CentralManager? _centralManager;
  PeripheralManager? _peripheralManager;

  final UwbHostApi _hostApi = UwbHostApi();

  Uwb() {
    UwbFlutterApi.setup(this);
  }

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
    // This is the internal handshake logic.
    // It receives the iOS-generated config data and forwards it to the peer via BLE.
    _oobBle?.sendShareableConfig(peerId: peerId, data: data);
  }

  // --- Public API ---

  @override
  Stream<UwbSessionState> get uwbSessionStateStream =>
      _uwbSessionStateStream.stream.asBroadcastStream();

  @override
  Stream<List<UwbDevice>> get uwbDataStream =>
      _uwbDataStreamController.stream.asBroadcastStream();
      
  @override
  Stream<PermissionAction> get permissionRequestStream =>
      _permissionRequestController.stream.asBroadcastStream();

  Future<void> start({
    String? deviceName,
    required String serviceUuid,
    required String handshakeCharacteristicUuid,
    required String platformCharacteristicUuid,
    UwbSessionConfig? config,
  }) async {
    if (_oobBle != null) {
      debugPrint("UWB session already active. Please stop the current session before starting a new one.");
      return;
    }
    
    _centralManager = CentralManager();
    _peripheralManager = PeripheralManager();

    if (config == null) {
      debugPrint("Warning: No UwbSessionConfig provided. Using default values.");
    }

    final sessionConfig = config ?? UwbSessionConfig(
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

  @override
  Future<void> stopRanging(String peerAddress) async {
    try {
      await _hostApi.stopRanging(peerAddress);
    } on PlatformException catch (e) {
      _parsePlatformException(e);
    }
  }

  @override
  Future<void> stopUwbSessions() async {
    try {
      _rangingDevices.clear();
      return await _hostApi.stopUwbSessions();
    } on PlatformException catch (e) {
      _parsePlatformException(e);
    }
  }

  @override
  Future<bool> isUwbSupported() async {
    return await _hostApi.isUwbSupported();
  }

  // --- Internal Methods (called by OobBle) ---

  @override
  Future<void> startRanging(Uint8List peerAddress, UwbSessionConfig config) async {
    try {
      return await _hostApi.startRanging(peerAddress, config);
    } on PlatformException catch (e) {
      _parsePlatformException(e);
    }
  }

  @override
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
