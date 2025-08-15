import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:uwb/src/uwb.g.dart';
import 'package:uwb/src/uwb_ble_manager.dart';

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
  final Map<String, DiscoveredPeer> _activePeers = {};

  final _peersController = StreamController<UwbPeer>.broadcast();
  final _rangingErrorController = StreamController<String>.broadcast();

  Stream<UwbPeer> get peerStream => _peersController.stream;
  Stream<String> get rangingErrorStream => _rangingErrorController.stream;

  Future<void> start(String deviceName, String serviceUUIDDigest) async {
    await stop(); 
    _localDeviceName = deviceName;
    
    const uuid = Uuid();
    final serviceUuid = uuid.v5(Uuid.NAMESPACE_URL, '$serviceUUIDDigest-service');
    final handshakeUuid = uuid.v5(Uuid.NAMESPACE_URL, '$serviceUUIDDigest-handshake');
    final platformUuid = uuid.v5(Uuid.NAMESPACE_URL, '$serviceUUIDDigest-platform');

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
      // Per Apple's docs, the accessory (Android) initiates the handshake by sending its config data first.
      if (Platform.isAndroid && peer.platform == 'ios') {
        debugPrint("[UWB INTERFACE] Android device is accessory. Getting accessory config data.");
        final accessoryConfigData = await _hostApi.getAndroidAccessoryConfigurationData();
        debugPrint("[UWB INTERFACE] Sending Android accessory config to iOS peer via BLE.");
        await _bleManager!.sendHandshakeData(peer.peripheral, accessoryConfigData);
      } else {
        // iOS-to-iOS or a decided controller in a same-platform scenario initiates.
        bool isController = false;
        if (localDeviceName.compareTo(peer.deviceName) < 0) {
          isController = true;
        }

        if (isController && Platform.isIOS && peer.platform == 'ios') {
          debugPrint("[UWB INTERFACE] iOS device is controller to another iOS. Getting token from native.");
          final token = await _hostApi.startIosController();
          debugPrint("[UWB INTERFACE] Sending iOS token to BLE manager.");
          await _bleManager!.sendHandshakeData(peer.peripheral, token);
        }
      }
    } catch (e) {
      _rangingErrorController.add("Error during handshake initiation: $e");
    }
  }

  Future<void> _handleBleDataReceived(BleDataReceived event) async {
    final peer = _activePeers[event.peripheral.uuid.toString()];
    if (peer == null) return;

    try {
      if (Platform.isIOS && peer.platform == 'ios') {
        debugPrint("[UWB INTERFACE] iOS received token from iOS peer. Passing to native to start accessory mode.");
        await _hostApi.startIosAccessory(event.data);
      } 
      // This device is iOS (controller) and it has received the initial config from the Android accessory.
      else if (Platform.isIOS && peer.platform == 'android') {
        debugPrint("[UWB INTERFACE] iOS (Controller) received accessory config from Android. Passing to native to initialize.");
        final shareableConfig = await _hostApi.initializeAndroidController(event.data);
        debugPrint("[UWB INTERFACE] iOS received shareable config from native. Sending it back to Android peer via BLE.");
        await _bleManager!.sendHandshakeData(peer.peripheral, shareableConfig);
        debugPrint("[UWB INTERFACE] iOS starting ranging with Android peer.");
        await _hostApi.startAndroidRanging(shareableConfig, true);
      } 
      // This device is Android (accessory) and it has received the shareable config back from the iOS controller.
      else if (Platform.isAndroid && peer.platform == 'ios') {
        debugPrint("[UWB INTERFACE] Android (Accessory) received shareable config from iOS. Passing to native to start ranging.");
        await _hostApi.startAndroidRanging(event.data, false);
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
