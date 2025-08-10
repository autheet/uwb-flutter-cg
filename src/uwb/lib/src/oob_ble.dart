import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:uwb/src/uwb.dart';

class OobBle {
  final FlutterUwb _uwb = FlutterUwb();
  final CentralManager _centralManager;
  final PeripheralManager _peripheralManager;
  final UUID _serviceUuid;
  final UUID _handshakeCharacteristicUuid;
  final UUID _platformCharacteristicUuid;
  final String? _deviceName;

  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>?
      _centralStateSubscription;
  StreamSubscription<DiscoveredEventArgs>? _discoverySubscription;

  final Map<String, Peripheral> _discoveredPeripherals = {};
  bool _isActive = false;

  OobBle({
    required String serviceUuid,
    required String handshakeCharacteristicUuid,
    required String platformCharacteristicUuid,
    String? deviceName,
  })  : _centralManager = CentralManager(),
        _peripheralManager = PeripheralManager(),
        _serviceUuid = UUID.fromString(serviceUuid),
        _handshakeCharacteristicUuid =
            UUID.fromString(handshakeCharacteristicUuid),
        _platformCharacteristicUuid =
            UUID.fromString(platformCharacteristicUuid),
        _deviceName = deviceName;

  Future<void> start() async {
    _listenToStateChanges();
    await _handleState(_centralManager.state);
  }

  void dispose() {
    _isActive = false;
    _stopAdvertising();
    _stopDiscovery();
    _centralStateSubscription?.cancel();
    _discoveredPeripherals.clear();
    _uwb.dispose();
  }

  void _listenToStateChanges() {
    _centralStateSubscription?.cancel();
    _centralStateSubscription = _centralManager.stateChanged.listen((event) {
      _handleState(event.state);
    });
  }

  Future<void> _handleState(BluetoothLowEnergyState state) async {
    if (state == BluetoothLowEnergyState.poweredOn) {
      if (!_isActive) {
        _isActive = true;
        await _startBleOperations();
      }
    } else {
      _isActive = false;
      _stopAdvertising();
      _stopDiscovery();
    }
  }

  Future<void> _startBleOperations() async {
    await _startAdvertising();
    await _startDiscovery();
  }

  Future<void> _startAdvertising() async {
    final platformCharacteristic = GATTCharacteristic.immutable(
      uuid: _platformCharacteristicUuid,
      value: Uint8List.fromList(utf8.encode(Platform.operatingSystem)),
      descriptors: [],
    );

    final handshakeCharacteristic = GATTCharacteristic.mutable(
      uuid: _handshakeCharacteristicUuid,
      properties: [
        GATTCharacteristicProperty.write,
        GATTCharacteristicProperty.notify,
      ],
      permissions: [
        GATTCharacteristicPermission.read,
        GATTCharacteristicPermission.write,
      ],
      descriptors: [],
    );

    await _peripheralManager.addService(
      GATTService(
        uuid: _serviceUuid,
        isPrimary: true,
        includedServices: [],
        characteristics: [
          platformCharacteristic,
          handshakeCharacteristic,
        ],
      ),
    );

    await _peripheralManager.startAdvertising(
      Advertisement(
        name: _deviceName,
        serviceUUIDs: [_serviceUuid],
      ),
    );
  }

  Future<void> _stopAdvertising() async {
    await _peripheralManager.stopAdvertising();
  }

  Future<void> _startDiscovery() async {
    _discoverySubscription?.cancel();
    _discoverySubscription = _centralManager.discovered.listen((event) {
      final deviceName = event.advertisement.name;
      if (deviceName != null &&
          deviceName.isNotEmpty &&
          !_discoveredPeripherals.containsKey(event.peripheral.uuid.toString())) {
        _discoveredPeripherals[event.peripheral.uuid.toString()] =
            event.peripheral;
        _handlePeripheral(event.peripheral, deviceName);
      }
    });

    await _centralManager.startDiscovery(
      serviceUUIDs: [_serviceUuid],
    );
  }

  Future<void> _stopDiscovery() async {
    await _centralManager.stopDiscovery();
    _discoverySubscription?.cancel();
  }

  void _handlePeripheral(Peripheral peripheral, String peerDeviceName) async {
    try {
      await _centralManager.connect(peripheral);
      await Future.delayed(const Duration(milliseconds: 500));
      final services = await _centralManager.discoverGATT(peripheral);

      final gattService = services.firstWhere((s) => s.uuid == _serviceUuid);
      final handshakeCharacteristic = gattService.characteristics
          .firstWhere((c) => c.uuid == _handshakeCharacteristicUuid);

      if (Platform.isIOS) {
        final localEndpoint = await _uwb.getLocalEndpoint();
        await _centralManager.writeCharacteristic(
          peripheral,
          handshakeCharacteristic,
          value: localEndpoint,
          type: GATTCharacteristicWriteType.withResponse,
        );
      } else { // Current device is Android
        final peerEndpoint = await _centralManager.readCharacteristic(
            peripheral, handshakeCharacteristic);
        final isController = _deviceName!.compareTo(peerDeviceName) < 0;
        await _uwb.startRanging(peerEndpoint, isController: isController);
      }
    } catch (e) {
      debugPrint(
          "Error handling peripheral: $e. Disconnecting and restarting discovery.");
      try {
        await _centralManager.disconnect(peripheral);
        _discoveredPeripherals.remove(peripheral.uuid.toString());
      } catch (disconnectError) {
        debugPrint("Error during disconnect: $disconnectError");
      }
    }
  }
}
