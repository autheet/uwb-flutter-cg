import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:uwb/src/uwb.g.dart';
import 'package:uwb/src/uwb_ble_manager.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';

// --- Public Facing Data Class ---

/// A public data class representing a nearby device, with fused BLE and UWB data.
class UwbPeer {
  final String peerAddress; // The BLE peripheral's UUID.
  final String deviceName;
  final String platform; // 'ios' or 'android'
  final int rssi;
  final double? distance;
  final double? azimuth;
  final double? elevation;

  UwbPeer({
    required this.peerAddress,
    required this.deviceName,
    required this.platform,
    required this.rssi,
    this.distance,
    this.azimuth,
    this.elevation,
  });

  UwbPeer copyWith({double? distance, double? azimuth, double? elevation}) {
    return UwbPeer(
      peerAddress: this.peerAddress,
      deviceName: this.deviceName,
      platform: this.platform,
      rssi: this.rssi,
      distance: distance ?? this.distance,
      azimuth: azimuth ?? this.azimuth,
      elevation: elevation ?? this.elevation,
    );
  }
}

// --- Public Plugin Class ---
class FlutterUwb implements UwbFlutterApi {
  static final FlutterUwb _instance = FlutterUwb._internal();
  factory FlutterUwb() => _instance;

  FlutterUwb._internal() {
    UwbFlutterApi.setup(this);
  }

  final UwbHostApi _hostApi = UwbHostApi();
  UwbBleManager? _bleManager;
  StreamSubscription? _peerDiscoveredSubscription;
  StreamSubscription? _peerLostSubscription;
  StreamSubscription? _bleDataReceivedSubscription;
  
  String? _localDeviceName;
  String? _serviceUUIDDigest;
  final Map<String, DiscoveredPeer> _activePeers = {};

  final _peersController = StreamController<UwbPeer>.broadcast();
  final _rangingErrorController = StreamController<String>.broadcast();

  Stream<UwbPeer> get peerStream => _peersController.stream;
  Stream<String> get rangingErrorStream => _rangingErrorController.stream;

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses;
    if (Platform.isAndroid) {
      statuses = await [
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.nearbyWifiDevices,
      ].request();
    } else if (Platform.isIOS) {
      statuses = await [
        Permission.bluetooth,
      ].request();
    } else {
      return;
    }
    debugPrint("[UWB INTERFACE] Permission statuses: $statuses");
  }

  Future<void> start(String deviceName, String serviceUUIDDigest) async {
    await stop(); 
    _localDeviceName = deviceName;
    _serviceUUIDDigest = serviceUUIDDigest;
    
    await _requestPermissions();

    const uuid = Uuid();
    final baseUuid = sha256.convert(utf8.encode(sha256.convert(utf8.encode(serviceUUIDDigest)).toString())).toString();
    final serviceUuid = uuid.v5(Uuid.NAMESPACE_URL, '$baseUuid-service');
    final handshakeUuid = uuid.v5(Uuid.NAMESPACE_URL, '$baseUuid-handshake');
    final platformUuid = uuid.v5(Uuid.NAMESPACE_URL, '$baseUuid-platform');

    _bleManager = UwbBleManager(
      serviceUuid: serviceUuid,
      handshakeCharacteristicUuid: handshakeUuid,
      platformCharacteristicUuid: platformUuid,
      deviceName: deviceName,
    );
    
    _peerDiscoveredSubscription = _bleManager!.peerDiscoveredStream.listen(_handlePeerDiscovered);
    _peerLostSubscription = _bleManager!.peerLostStream.listen(_handlePeerLost);
    _bleDataReceivedSubscription = _bleManager!.bleDataReceivedStream.listen(_handleBleDataReceived);
    
    await _bleManager!.start();
    await _hostApi.start(deviceName, serviceUUIDDigest);
  }

  Future<void> stop() async {
    _localDeviceName = null;
    _serviceUUIDDigest = null;
    await _peerDiscoveredSubscription?.cancel();
    await _peerLostSubscription?.cancel();
    await _bleDataReceivedSubscription?.cancel();
    _bleManager?.dispose();
    _bleManager = null;
    _activePeers.clear();
    await _hostApi.stop();
  }
  
  void _handlePeerDiscovered(DiscoveredPeer peer) {
    _activePeers[peer.peripheral.uuid.toString()] = peer;
    _peersController.add(UwbPeer(
      peerAddress: peer.peripheral.uuid.toString(),
      deviceName: peer.deviceName,
      platform: peer.platform,
      rssi: peer.rssi,
    ));
    _initiateHandshake(peer);
  }
  
  void _handlePeerLost(DiscoveredPeer peer) {
    _activePeers.remove(peer.peripheral.uuid.toString());
  }

  Future<void> _initiateHandshake(DiscoveredPeer peer) async {
    final localDeviceName = _localDeviceName;
    if (localDeviceName == null) return;
    
    try {
      if (Platform.isAndroid && peer.platform == 'ios') {
        debugPrint("[UWB INTERFACE] Android device is accessory. Getting accessory config data.");
        final accessoryConfigData = await _hostApi.getAndroidAccessoryConfigurationData();
        debugPrint("[UWB INTERFACE] Sending Android accessory config to iOS peer via BLE.");
        await _bleManager!.sendHandshakeData(peer.peripheral, accessoryConfigData);
      } else if (Platform.isIOS && peer.platform == 'android') {
        // iOS is the controller, but it waits for the Android accessory to send its config first.
        // No action is needed here, the process is initiated by the accessory.
      } else {
        // iOS-to-iOS or Android-to-Android
        bool isController = localDeviceName.compareTo(peer.deviceName) < 0;
        if (isController) {
          if (Platform.isIOS) {
            debugPrint("[UWB INTERFACE] iOS device is controller to another iOS. Getting token from native.");
            final token = await _hostApi.startIosController();
            debugPrint("[UWB INTERFACE] Sending iOS token to BLE manager.");
            await _bleManager!.sendHandshakeData(peer.peripheral, token);
          }
        }
      }
    } catch (e) {
      _rangingErrorController.add("Error during handshake initiation: $e");
    }
  }

  Future<void> _handleBleDataReceived(BleDataReceived event) async {
    final peer = _activePeers[event.peripheral.uuid.toString()];
    if (peer == null || _serviceUUIDDigest == null) return;

    try {
      final sessionKeyInfo = Uint8List.fromList(sha256.convert(utf8.encode(_serviceUUIDDigest!)).bytes);
      final sessionId = _serviceUUIDDigest!.hashCode;

      if (Platform.isIOS && peer.platform == 'ios') {
        debugPrint("[UWB INTERFACE] iOS received token from iOS peer. Passing to native to start accessory mode.");
        await _hostApi.startIosAccessory(event.data);
      } 
      // This device is iOS (controller) and it has received the initial config from the Android accessory.
      else if (Platform.isIOS && peer.platform == 'android') {
        debugPrint("[UWB INTERFACE] iOS (Controller) received accessory config from Android. Passing to native to initialize.");
        final shareableConfig = await _hostApi.initializeAndroidController(event.data, sessionKeyInfo, sessionId.toInt());
        debugPrint("[UWB INTERFACE] iOS received shareable config from native. Sending it back to Android peer via BLE.");
        await _bleManager!.sendHandshakeData(peer.peripheral, shareableConfig);
        debugPrint("[UWB INTERFACE] iOS starting ranging with Android peer.");
        await _hostApi.startAndroidRanging(shareableConfig, true, sessionKeyInfo, sessionId.toInt());
      } 
      // This device is Android (accessory) and it has received the shareable config back from the iOS controller.
      else if (Platform.isAndroid && peer.platform == 'ios') {
        debugPrint("[UWB INTERFACE] Android (Accessory) received shareable config from iOS. Passing to native to start ranging.");
        await _hostApi.startAndroidRanging(event.data, false, sessionKeyInfo, sessionId.toInt());
      }
    } catch (e) {
      _rangingErrorController.add("Error handling received BLE data: $e");
    }
  }

  @override
  void onRangingResult(RangingResult result) {
    final peerKey = _activePeers.keys.firstWhere((k) => _activePeers[k]!.deviceName == result.deviceName, orElse: () => '');
    if (peerKey.isNotEmpty) {
      final peer = _activePeers[peerKey]!;
      final updatedPeer = UwbPeer(
        peerAddress: peer.peripheral.uuid.toString(),
        deviceName: peer.deviceName,
        platform: peer.platform,
        rssi: peer.rssi,
        distance: result.distance,
        azimuth: result.azimuth,
        elevation: result.elevation,
      );
      _peersController.add(updatedPeer);
    }
  }

  @override
  void onRangingError(String error) {
    _rangingErrorController.add(error);
  }
  
  @override
  void onBleDataReceived(Uint8List data) {}
  @override
  void onPeerDiscovered(String deviceName, String peerAddress) {}
  @override
  void onPeerLost(String deviceName, String peerAddress) {}
  
  void dispose() {
    _peersController.close();
    _rangingErrorController.close();
    stop();
  }
}
