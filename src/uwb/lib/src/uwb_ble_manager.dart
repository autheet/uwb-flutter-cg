import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';

/// Data class holding information about a peer discovered via BLE.
class DiscoveredPeer {
  final Peripheral peripheral;
  final String deviceName;
  final String platform;
  final int rssi; // RSSI value at the time of discovery.

  DiscoveredPeer({
    required this.peripheral,
    required this.deviceName,
    required this.platform,
    required this.rssi,
  });
}

/// Data class for data received over the BLE handshake characteristic.
class BleDataReceived {
  final Peripheral peripheral;
  final Uint8List data;
  BleDataReceived({required this.peripheral, required this.data});
}

/// Manages all BLE discovery and communication for the UWB handshake.
class UwbBleManager {
  CentralManager _centralManager;
  PeripheralManager _peripheralManager;
  final UUID _serviceUuid;
  final UUID _handshakeCharacteristicUuid;
  final UUID _platformCharacteristicUuid;
  final String _deviceName;

  StreamSubscription? _centralStateSubscription;
  StreamSubscription? _discoverySubscription;
  StreamSubscription? _writeRequestedSubscription;
  StreamSubscription? _notifySubscription;

  final Map<String, Peripheral> _discoveredPeripherals = {};
  final Map<String, String> _peripheralIdToName = {};
  final Map<String, GATTCharacteristic> _handshakeCharacteristics = {};
  final Map<String, StreamSubscription> _connectionStateSubscriptions = {};

  bool _isActive = false;

  final _peerDiscoveredController = StreamController<DiscoveredPeer>.broadcast();
  final _peerLostController = StreamController<DiscoveredPeer>.broadcast();
  final _bleDataReceivedController = StreamController<BleDataReceived>.broadcast();

  Stream<DiscoveredPeer> get peerDiscoveredStream => _peerDiscoveredController.stream;
  Stream<DiscoveredPeer> get peerLostStream => _peerLostController.stream;
  Stream<BleDataReceived> get bleDataReceivedStream => _bleDataReceivedController.stream;

  UwbBleManager({
    required String serviceUuid,
    required String handshakeCharacteristicUuid,
    required String platformCharacteristicUuid,
    required String deviceName,
  })  : _centralManager = CentralManager(),
        _peripheralManager = PeripheralManager(),
        _serviceUuid = UUID.fromString(serviceUuid),
        _handshakeCharacteristicUuid = UUID.fromString(handshakeCharacteristicUuid),
        _platformCharacteristicUuid = UUID.fromString(platformCharacteristicUuid),
        _deviceName = deviceName;

  Future<void> start() async {
    _listenToStateChanges();
    await _handleState(_centralManager.state);
  }

  void _listenToStateChanges() {
    _centralStateSubscription?.cancel();
    _centralStateSubscription = _centralManager.stateChanged.listen((event) {
      _handleState(event.state);
    });
  }

  Future<void> _handleState(BluetoothLowEnergyState state) async {
    debugPrint("[UWB BLE MANAGER] State changed: $state");
    switch (state) {
      case BluetoothLowEnergyState.poweredOn:
        if (!_isActive) {
          _isActive = true;
          debugPrint("[UWB BLE MANAGER] BLE powered on. Starting operations.");
          if (Platform.isAndroid) {
            _peripheralManager = PeripheralManager();
          }
          await _startAdvertising();
          await _startDiscovery();
        }
        break;
      case BluetoothLowEnergyState.unauthorized:
        debugPrint("[UWB BLE MANAGER] BLE unauthorized. Requesting authorization.");
        await _centralManager.authorize();
        break;
      default:
        if (_isActive) {
          debugPrint("[UWB BLE MANAGER] BLE state is $state. Stopping operations.");
          _isActive = false;
          await _stopAdvertising();
          await _stopDiscovery();
        }
        break;
    }
  }

  Future<void> _startAdvertising() async {
    _writeRequestedSubscription = _peripheralManager.characteristicWriteRequested.listen((event) {
      final peripheral = _discoveredPeripherals[event.central.uuid.toString()];
      if (peripheral != null) {
        final deviceName = _peripheralIdToName[peripheral.uuid.toString()] ?? 'Unknown Device';
        debugPrint('Received handshake data from $deviceName');
        _bleDataReceivedController.add(BleDataReceived(peripheral: peripheral, data: event.request.value));
      }
    });

    final platformCharacteristic = GATTCharacteristic.immutable(
      uuid: _platformCharacteristicUuid,
      value: Uint8List.fromList(utf8.encode(Platform.operatingSystem)),
      descriptors: [],
    );

    final handshakeCharacteristic = GATTCharacteristic.mutable(
      uuid: _handshakeCharacteristicUuid,
      properties: [GATTCharacteristicProperty.write, GATTCharacteristicProperty.notify],
      permissions: [GATTCharacteristicPermission.write],
      descriptors: [],
    );

    await _peripheralManager.removeAllServices();
    
    await _peripheralManager.addService(
      GATTService(
        uuid: _serviceUuid,
        isPrimary: true,
        includedServices: [],
        characteristics: [platformCharacteristic, handshakeCharacteristic],
      ),
    );

    await _peripheralManager.startAdvertising(
      Advertisement(name: _deviceName, serviceUUIDs: [_serviceUuid]),
    );
  }

  Future<void> _startDiscovery() async {
    _discoverySubscription?.cancel();
    _discoverySubscription = _centralManager.discovered.listen((event) {
      final deviceName = event.advertisement.name;
      if (deviceName != null && deviceName.isNotEmpty && !_discoveredPeripherals.containsKey(event.peripheral.uuid.toString())) {
        _peripheralIdToName[event.peripheral.uuid.toString()] = deviceName;
        _discoveredPeripherals[event.peripheral.uuid.toString()] = event.peripheral;
        _connectAndDiscover(event.peripheral, deviceName, event.rssi);
      }
    });
    await _centralManager.startDiscovery(serviceUUIDs: [_serviceUuid]);
  }

  Future<void> _connectAndDiscover(Peripheral peripheral, String peerDeviceName, int rssi) async {
    try {
      await _centralManager.connect(peripheral);

      _connectionStateSubscriptions[peripheral.uuid.toString()] = _centralManager.connectionStateChanged.listen((event) {
        if (event.peripheral == peripheral && event.state == ConnectionState.disconnected) {
          final peer = DiscoveredPeer(peripheral: peripheral, deviceName: peerDeviceName, platform: "unknown", rssi: rssi);
          _peerLostController.add(peer);
          _cleanupConnection(peripheral);
        }
      });

      final services = await _centralManager.discoverGATT(peripheral);
      final service = services.firstWhere((s) => s.uuid == _serviceUuid);
      final platformCharacteristic = service.characteristics.firstWhere((c) => c.uuid == _platformCharacteristicUuid);
      final platformBytes = await _centralManager.readCharacteristic(peripheral, platformCharacteristic);
      final platform = utf8.decode(platformBytes);
      debugPrint('Discovered peer: $peerDeviceName on platform: $platform');
      
      final handshakeCharacteristic = service.characteristics.firstWhere((c) => c.uuid == _handshakeCharacteristicUuid);
      _handshakeCharacteristics[peripheral.uuid.toString()] = handshakeCharacteristic;
      await _centralManager.setCharacteristicNotifyState(peripheral, handshakeCharacteristic, state: true);
      _notifySubscription = _centralManager.characteristicNotified.listen((event) {
        if (event.characteristic.uuid == _handshakeCharacteristicUuid) {
          final deviceName = _peripheralIdToName[event.peripheral.uuid.toString()] ?? 'Unknown Device';
          debugPrint('Received handshake data from $deviceName');
          _bleDataReceivedController.add(BleDataReceived(peripheral: event.peripheral, data: event.value));
        }
      });

      final peer = DiscoveredPeer(peripheral: peripheral, deviceName: peerDeviceName, platform: platform, rssi: rssi);
      _peerDiscoveredController.add(peer);
    } catch (e) {
      debugPrint("Error connecting to peripheral: $e");
      _cleanupConnection(peripheral);
    }
  }
  
  Future<void> sendHandshakeData(Peripheral peripheral, Uint8List data) async {
    try {
      final deviceName = _peripheralIdToName[peripheral.uuid.toString()] ?? 'Unknown Device';
      final handshakeCharacteristic = _handshakeCharacteristics[peripheral.uuid.toString()];
      if (handshakeCharacteristic == null) {
        throw Exception('Handshake characteristic not found for $deviceName');
      }
      debugPrint('Sending handshake data to $deviceName');
      await _centralManager.writeCharacteristic(peripheral, handshakeCharacteristic, value: data, type: GATTCharacteristicWriteType.withoutResponse);
    } catch (e) {
      debugPrint("Error sending handshake data: $e");
    }
  }

  void dispose() {
    _isActive = false;
    _stopAdvertising();
    _stopDiscovery();
    _centralStateSubscription?.cancel();
    _writeRequestedSubscription?.cancel();
    _notifySubscription?.cancel();
    _discoveredPeripherals.values.forEach(_cleanupConnection);
    _peripheralIdToName.clear();
    _handshakeCharacteristics.clear();
    _discoveredPeripherals.clear();
    _peerDiscoveredController.close();
    _peerLostController.close();
    _bleDataReceivedController.close();
  }

  void _cleanupConnection(Peripheral peripheral) {
    _connectionStateSubscriptions[peripheral.uuid.toString()]?.cancel();
    _connectionStateSubscriptions.remove(peripheral.uuid.toString());
    _peripheralIdToName.remove(peripheral.uuid.toString());
    _handshakeCharacteristics.remove(peripheral.uuid.toString());
    _centralManager.disconnect(peripheral).catchError((e) => debugPrint("Error disconnecting: $e"));
  }

  Future<void> _stopAdvertising() async {
    try {
      await _peripheralManager.stopAdvertising();
    } catch (e) {
      // Ignore errors if not advertising
    }
  }

  Future<void> _stopDiscovery() async {
    try {
      await _centralManager.stopDiscovery();
    } catch(e) {
      // Ignore errors if not scanning
    }
    _discoverySubscription?.cancel();
  }
}
