import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:uwb/flutter_uwb.dart';
import 'package:uwb/src/defs.dart';

class OobBle {
  final Uwb _uwb;
  final CentralManager _centralManager;
  final PeripheralManager _peripheralManager;
  final UUID _serviceUuid;
  final UUID _rxCharacteristicUuid;
  final UUID _txCharacteristicUuid;
  final UwbSessionConfig _config;
  final String? _deviceName;

  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>? _centralStateSubscription;
  StreamSubscription<DiscoveredEventArgs>? _discoverySubscription;
  StreamSubscription<GATTCharacteristicNotifiedEventArgs>? _notificationSubscription;
  
  bool _isActive = false;

  OobBle(
    this._uwb,
    this._centralManager,
    this._peripheralManager,
    this._serviceUuid,
    this._rxCharacteristicUuid,
    this._txCharacteristicUuid,
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
      _stopDiscovery();
      _handlePeripheral(event.peripheral);
    });

    _notificationSubscription?.cancel();
    _notificationSubscription = _centralManager.characteristicNotified.listen((event) {
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

  void _handlePeripheral(Peripheral peripheral) async {
    try {
      await _centralManager.connect(peripheral);
      final services = await _centralManager.discoverGATT(peripheral);
      final gattService = services.firstWhere((s) => s.uuid == _serviceUuid);

      final rxCharacteristic = gattService.characteristics.firstWhere((c) => c.uuid == _rxCharacteristicUuid);
      final txCharacteristic = gattService.characteristics.firstWhere((c) => c.uuid == _txCharacteristicUuid);

      await _centralManager.setCharacteristicNotifyState(peripheral, txCharacteristic, state: true);
      
      final localAddress = await _uwb.getLocalUwbAddress();
      await _centralManager.writeCharacteristic(peripheral, rxCharacteristic, value: localAddress, type: GATTCharacteristicWriteType.withResponse);

    } catch (e) {
      debugPrint("Error handling peripheral: $e");
      await _startDiscovery();
    }
  }

  void _onNotificationReceived(Uint8List value) {
    if (value.isNotEmpty) {
      _uwb.startRanging(value, _config);
    }
  }
}
