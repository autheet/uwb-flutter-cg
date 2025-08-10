import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:uwb/flutter_uwb.dart';

class OobBle {
  final Uwb _uwb;
  final CentralManager _centralManager;
  final PeripheralManager _peripheralManager;
  final UUID _serviceUuid;
  final UUID _handshakeCharacteristicUuid;
  final UUID _platformCharacteristicUuid;
  final UwbSessionConfig _config;
  final String? _deviceName;

  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>?
      _centralStateSubscription;
  StreamSubscription<DiscoveredEventArgs>? _discoverySubscription;
  StreamSubscription<GATTCharacteristicNotifiedEventArgs>?
      _notificationSubscription;

  final Map<String, Peripheral> _discoveredPeripherals = {};
  bool _isActive = false;

  OobBle(
    this._uwb,
    this._centralManager,
    this._peripheralManager,
    this._serviceUuid,
    this._handshakeCharacteristicUuid,
    this._platformCharacteristicUuid,
    this._config, {
    String? deviceName,
  }) : _deviceName = deviceName;

  Future<void> start() async {
    _listenToStateChanges();
    await _handleState(_centralManager.state);
  }

  void dispose() {
    _isActive = false;
    _stopAdvertising();
    _stopDiscovery();
    _centralStateSubscription?.cancel();
    _notificationSubscription?.cancel();
    _discoveredPeripherals.clear();
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
      if (!_discoveredPeripherals.containsKey(event.peripheral.uuid.toString())) {
        _discoveredPeripherals[event.peripheral.uuid.toString()] = event.peripheral;
        _handlePeripheral(event.peripheral);
      }
    });

    _notificationSubscription?.cancel();
    _notificationSubscription =
        _centralManager.characteristicNotified.listen((event) {
      _onNotificationReceived(event.value);
    });

    await _centralManager.startDiscovery(
      serviceUUIDs: [_serviceUuid],
    );
  }

  Future<void> _stopDiscovery() async {
    await _centralManager.stopDiscovery();
    _discoverySubscription?.cancel();
  }

  Future<void> sendShareableConfig({required String peerId, required Uint8List data}) async {
    final peripheral = _discoveredPeripherals[peerId];
    if (peripheral == null) {
      debugPrint("Error: Could not find peripheral with ID $peerId to send shareable config.");
      return;
    }

    try {
      final services = await _centralManager.discoverGATT(peripheral);
      final service = services.firstWhere((s) => s.uuid == _serviceUuid);
      final characteristic = service.characteristics.firstWhere((c) => c.uuid == _handshakeCharacteristicUuid);
      
      await _centralManager.writeCharacteristic(peripheral, characteristic, value: data, type: GATTCharacteristicWriteType.withResponse);
      debugPrint("Successfully sent shareable config to peer $peerId");
    } catch (e) {
      debugPrint("Error sending shareable config to peer $peerId: $e");
    }
  }

  void _handlePeripheral(Peripheral peripheral) async {
    try {
      await _centralManager.connect(peripheral);
      await Future.delayed(const Duration(milliseconds: 500));
      final services = await _centralManager.discoverGATT(peripheral);

      final gattService = services.firstWhere((s) => s.uuid == _serviceUuid);
      final handshakeCharacteristic = gattService.characteristics.firstWhere((c) => c.uuid == _handshakeCharacteristicUuid);
      final platformCharacteristic = gattService.characteristics.firstWhere((c) => c.uuid == _platformCharacteristicUuid);

      final platformBytes = await _centralManager.readCharacteristic(peripheral, platformCharacteristic);
      final platform = String.fromCharCodes(platformBytes);

      await _centralManager.setCharacteristicNotifyState(peripheral,
          handshakeCharacteristic, state: true);

      if (platform == 'ios') {
        // We are Android, peer is iOS. We send our local address (which is NINearbyAccessoryConfiguration compatible)
        final localAddress = await _uwb.getLocalUwbAddress();
        await _centralManager.writeCharacteristic(peripheral, handshakeCharacteristic, value: localAddress, type: GATTCharacteristicWriteType.withResponse);
      } else {
        // We are iOS, peer is Android. We send our NIDiscoveryToken.
        final localAddress = await _uwb.getLocalUwbAddress();
        await _centralManager.writeCharacteristic(peripheral, handshakeCharacteristic, value: localAddress, type: GATTCharacteristicWriteType.withResponse);
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

  void _onNotificationReceived(Uint8List value) {
    if (value.isNotEmpty) {
      if (Platform.isIOS) {
        // On iOS, we receive the NINearbyAccessoryConfiguration here
        _uwb.startRanging(value, _config);
      } else {
        // On Android, we receive the NIDiscoveryToken here
        // We need to generate the NINearbyAccessoryConfiguration and send it back
        _uwb.startRanging(value, _config);
      }
    }
  }
}