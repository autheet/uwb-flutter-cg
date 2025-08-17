import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // Add this import for PlatformException
import 'package:uuid/uuid.dart';
import 'package:uwb/src/uwb.g.dart';
import 'package:uwb/src/uwb_ble_manager.dart';
import 'package:crypto/crypto.dart';
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
      peerAddress: peerAddress,
      deviceName: deviceName,
      platform: platform,
      rssi: rssi,
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
    UwbFlutterApi.setUp(this);
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

    try {
      await _hostApi.start(deviceName, serviceUUIDDigest);
    } on PlatformException catch (e) {
      // Catch the specific permission error from the native iOS code
      if (e.code == 'PERMISSION_DENIED') {
        debugPrint("[UWB INTERFACE] Native iOS permission denied. Opening app settings.");
        // Guide the user to the settings app to manually enable the permission.
        await openAppSettings();
      } else {
        // Re-throw any other platform exceptions
        rethrow;
      }
    }
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
    initiateHandshake(peer.peripheral.uuid.toString());
  }
  
  void _handlePeerLost(DiscoveredPeer peer) {
    _activePeers.remove(peer.peripheral.uuid.toString());
  }

  Future<void> initiateHandshake(String peerAddress) async {
    final peer = _activePeers[peerAddress];
    if (peer == null || _localDeviceName == null) {
      debugPrint("[UWB INTERFACE] Error: Peer or local device name not found.");
      return;
    }

    try {
      // Case 1: iOS <-> iOS (Apple Peer Protocol)
      if (Platform.isIOS && peer.platform == 'ios') {
        debugPrint("[UWB INTERFACE] iOS device initiating peer-to-peer handshake with another iOS device.");
        final token = await _hostApi.startIosController();
        await _bleManager!.sendHandshakeData(peer.peripheral, token);
        return;
      }

      // Case 2: Android <-> iOS (FiRa Protocol)
      if (Platform.isAndroid && peer.platform == 'ios') {
        // Android is always the accessory, it sends its address first.
        debugPrint("[UWB INTERFACE] Android (Accessory) initiating handshake with iOS (Controller).");
        final accessoryAddress = await _hostApi.getAccessoryAddress();
        await _bleManager!.sendHandshakeData(peer.peripheral, accessoryAddress);
      } else if (Platform.isIOS && peer.platform == 'android') {
        // iOS is always the controller, it waits for the accessory's address.
        debugPrint("[UWB INTERFACE] iOS (Controller) waiting for handshake from Android (Accessory).");
      }

      // Case 3: Android <-> Android (FiRa Protocol)
      else if (Platform.isAndroid && peer.platform == 'android') {
        final isAccessory = _localDeviceName!.compareTo(peer.deviceName) < 0;
        if (isAccessory) {
          debugPrint("[UWB INTERFACE] Android (Accessory) initiating handshake with Android (Controller).");
          final accessoryAddress = await _hostApi.getAccessoryAddress();
          await _bleManager!.sendHandshakeData(peer.peripheral, accessoryAddress);
        } else {
          debugPrint("[UWB INTERFACE] Android (Controller) waiting for handshake from Android (Accessory).");
        }
      }
    } catch (e) {
      _rangingErrorController.add("Error during handshake initiation: $e");
    }
  }

  Future<void> _handleBleDataReceived(BleDataReceived event) async {
    final peer = _activePeers[event.peripheral.uuid.toString()];
    if (peer == null || _serviceUUIDDigest == null || _localDeviceName == null) return;

    try {
      // Case 1: iOS <-> iOS (Apple Peer Protocol)
      if (Platform.isIOS && peer.platform == 'ios') {
        debugPrint("[UWB INTERFACE] iOS received token from iOS peer. Starting accessory mode.");
        await _hostApi.startIosAccessory(event.data);
        return;
      }

      // --- FiRa Accessory Protocol ---
      bool isController = false;
      // An iOS device is always the controller to an Android accessory.
      if (Platform.isIOS && peer.platform == 'android') {
        isController = true;
      } 
      // For Android-to-Android, the device with the lexicographically greater name is the controller.
      else if (Platform.isAndroid && peer.platform == 'android') {
        isController = _localDeviceName!.compareTo(peer.deviceName) > 0;
      }
      
      if (isController) {
        debugPrint("[UWB INTERFACE] Controller received accessory address. Generating full UWB config.");
        final sessionKeyInfo = Uint8List.fromList(sha256.convert(utf8.encode(_serviceUUIDDigest!)).bytes);
        final sessionId = _serviceUUIDDigest!.hashCode;
        final config = await _hostApi.generateControllerConfig(event.data, sessionKeyInfo, sessionId);
        
        final configJson = {
          'uwbConfigId': config.uwbConfigId,
          'sessionId': config.sessionId,
          'sessionKeyInfo': config.sessionKeyInfo,
          'channel': config.channel,
          'preambleIndex': config.preambleIndex,
          'peerAddress': config.peerAddress,
        };
        final configString = jsonEncode(configJson);
        await _bleManager!.sendHandshakeData(peer.peripheral, Uint8List.fromList(utf8.encode(configString)));
      } 
      else { // This device is the Accessory
        debugPrint("[UWB INTERFACE] Accessory received full UWB config. Starting ranging session.");
        final configString = utf8.decode(event.data);
        final configJson = jsonDecode(configString) as Map<String, dynamic>;
        
        final config = UwbConfig(
          uwbConfigId: configJson['uwbConfigId'],
          sessionId: configJson['sessionId'],
          sessionKeyInfo: Uint8List.fromList(List<int>.from(configJson['sessionKeyInfo'])),
          channel: configJson['channel'],
          preambleIndex: configJson['preambleIndex'],
          peerAddress: Uint8List.fromList(List<int>.from(configJson['peerAddress'])),
        );
          
        await _hostApi.startAccessoryRanging(config);
      }
    } catch (e) {
      _rangingErrorController.add("Error handling received BLE data: $e");
    }
  }

  @override
  void onRangingResult(RangingResult result) {
    final peer = _activePeers.values.firstWhere((p) => p.deviceName == result.deviceName, orElse: () => _activePeers.values.first);
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