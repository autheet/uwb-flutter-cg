import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:uwb/src/uwb.g.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

// Re-export key data classes for the public API.
export 'package:uwb/src/uwb.g.dart'
    show UwbDevice, UwbRangingData, UwbSessionConfig;

/// A self-contained engine for UWB operations, handling BLE discovery and UWB ranging.
class Uwb implements UwbFlutterApi {
  final UwbHostApi _hostApi = UwbHostApi();
  _OobBleManager? _oobManager;

  final _devicesController = StreamController<List<UwbDevice>>.broadcast();
  final _errorController = StreamController<Object>.broadcast();

  Stream<List<UwbDevice>> get devicesStream => _devicesController.stream;
  Stream<Object> get errorStream => _errorController.stream;

  Uwb() {
    UwbFlutterApi.setup(this);
  }

  /// Starts the UWB process using a configuration provided by the caller.
  Future<void> start({
    required String deviceName, // This is the unique broadcastName
    required String serviceUuid,
    required String handshakeCharacteristicUuid,
    required String platformCharacteristicUuid,
    required UwbSessionConfig config,
  }) async {
    await stop();
    _oobManager = _OobBleManager(
      hostApi: _hostApi,
      deviceName: deviceName,
      serviceUuid: serviceUuid,
      handshakeCharacteristicUuid: handshakeCharacteristicUuid,
      platformCharacteristicUuid: platformCharacteristicUuid,
      config: config,
      onDevicesUpdated: (devices) => _devicesController.add(devices),
      onError: (error) => _errorController.add(error),
    );
    await _oobManager!.start();
  }

  Future<void> stop() async {
    await _oobManager?.dispose();
    _oobManager = null;
    try {
      await _hostApi.stopUwbSessions();
    } catch (e) {
      // Suppress errors on shutdown
    }
  }

  Future<bool> isUwbSupported() async => await _hostApi.isUwbSupported();

  void dispose() {
    stop();
    _devicesController.close();
    _errorController.close();
  }

  @override
  void onRangingResult(UwbDevice device) =>
      _oobManager?.handleRangingResult(device);
  @override
  void onRangingError(Object error) => _errorController.add(error);
  @override
  void onPeerDisconnected(UwbDevice device) =>
      _oobManager?.handlePeerDisconnected(device);
}

/// Private helper class to manage all BLE OOB logic.
class _OobBleManager {
  final CentralManager _centralManager = CentralManager();
  final PeripheralManager _peripheralManager = PeripheralManager();
  final UwbHostApi hostApi;
  final String deviceName,
      serviceUuid,
      handshakeCharacteristicUuid,
      platformCharacteristicUuid;
  final UwbSessionConfig config;
  final void Function(List<UwbDevice>) onDevicesUpdated;
  final void Function(Object) onError;

  final Map<String, UwbDevice> _knownDevices = {};
  final List<StreamSubscription> _subscriptions = [];
  Uint8List? _localUwbAddress;
  final String _platformName = Platform.isIOS ? "ios" : "android";

  _OobBleManager({
    required this.hostApi,
    required this.deviceName,
    required this.serviceUuid,
    required this.handshakeCharacteristicUuid,
    required this.platformCharacteristicUuid,
    required this.config,
    required this.onDevicesUpdated,
    required this.onError,
  });

  Future<void> start() async {
    _localUwbAddress = await hostApi.getLocalUwbAddress();
    _subscriptions.add(_centralManager.stateChanged.listen((event) {
      if (event.state == BluetoothLowEnergyState.poweredOn) {
        _startBleOperations();
      }
    }));
    if (_centralManager.state == BluetoothLowEnergyState.poweredOn) {
      _startBleOperations();
    }
  }

  Future<void> _startBleOperations() async {
    try {
      await _startAdvertising();
      await _startDiscovery();
    } catch (e) {
      onError(e);
    }
  }

  Future<void> _startAdvertising() async {
    final handshakeChar = GATTCharacteristic.mutable(
        uuid: UUID.fromString(handshakeCharacteristicUuid),
        properties: [
          GATTCharacteristicProperty.read,
          GATTCharacteristicProperty.write
        ],
        permissions: [
          GATTCharacteristicPermission.read,
          GATTCharacteristicPermission.write
        ],
        descriptors: []);
    final platformChar = GATTCharacteristic.mutable(
        uuid: UUID.fromString(platformCharacteristicUuid),
        properties: [GATTCharacteristicProperty.read],
        permissions: [GATTCharacteristicPermission.read],
        descriptors: []);
    final service = GATTService(
      uuid: UUID.fromString(serviceUuid),
      isPrimary: true,
      includedServices: [],
      characteristics: [handshakeChar, platformChar],
    );

    await _peripheralManager.addService(service);

    _subscriptions.add(
        _peripheralManager.characteristicReadRequested.listen((event) {
      try {
        if (event.characteristic.uuid == handshakeChar.uuid) {
          _peripheralManager.respondReadRequestWithValue(event.request,
              value: _localUwbAddress!);
        } else if (event.characteristic.uuid == platformChar.uuid) {
          _peripheralManager.respondReadRequestWithValue(event.request,
              value: Uint8List.fromList(_platformName.codeUnits));
        }
      } catch (e) {
        onError(e);
      }
    }));

    await _peripheralManager.startAdvertising(
      Advertisement(
          name: deviceName, serviceUUIDs: [UUID.fromString(serviceUuid)]),
    );
  }

  Future<void> _startDiscovery() async {
    _subscriptions.add(_centralManager.discovered.listen((event) {
      if (event.advertisement.name != null &&
          !_knownDevices.containsKey(event.peripheral.uuid.toString())) {
        _handleDiscoveredPeripheral(event.peripheral, event.advertisement.name!);
      }
    }));
    await _centralManager
        .startDiscovery(serviceUUIDs: [UUID.fromString(serviceUuid)]);
  }

  Future<void> _handleDiscoveredPeripheral(
      Peripheral peripheral, String peerBroadcastName) async {
    final peripheralId = peripheral.uuid.toString();
    try {
      await _centralManager.connect(peripheral);
      final services = await _centralManager.discoverGATT(peripheral);
      final service = services.firstWhere((s) =>
          s.uuid.toString().toLowerCase() == serviceUuid.toLowerCase());

      final handshakeChar = service.characteristics.firstWhere((c) =>
          c.uuid.toString().toLowerCase() ==
          handshakeCharacteristicUuid.toLowerCase());
      final platformChar = service.characteristics.firstWhere((c) =>
          c.uuid.toString().toLowerCase() ==
          platformCharacteristicUuid.toLowerCase());

      final peerUwbAddress =
          await _centralManager.readCharacteristic(peripheral, handshakeChar);
      final peerPlatformBytes =
          await _centralManager.readCharacteristic(peripheral, platformChar);
      final peerPlatformName = String.fromCharCodes(peerPlatformBytes);
      final isAccessory = peerPlatformName == "android";

      final newDevice =
          UwbDevice(address: peerUwbAddress, name: peerBroadcastName, rangingData: null);
      _knownDevices[peripheralId] = newDevice;
      onDevicesUpdated(_knownDevices.values.toList());

      hostApi.startRanging(peerUwbAddress, config, isAccessory);
    } catch (e) {
      onError(e);
    } finally {
      await _centralManager.disconnect(peripheral);
    }
  }

  void handleRangingResult(UwbDevice resultDevice) {
    UwbDevice? peer;
    String? peripheralId;

    for (var entry in _knownDevices.entries) {
      // The native layer only returns the address, so we match on that.
      if (listEquals(entry.value.address, resultDevice.address)) {
        peer = entry.value;
        peripheralId = entry.key;
        break;
      }
    }

    if (peer != null && peripheralId != null) {
      // We create a new device object that includes the original name.
      final updatedDevice = UwbDevice(
          address: peer.address,
          name: peer.name, // Preserve the broadcastName
          rangingData: resultDevice.rangingData);
      _knownDevices[peripheralId] = updatedDevice;
      onDevicesUpdated(_knownDevices.values.toList());
    }
  }

  void handlePeerDisconnected(UwbDevice device) {
    String? peripheralId;
    for (var entry in _knownDevices.entries) {
      if (listEquals(entry.value.address, device.address)) {
        peripheralId = entry.key;
        break;
      }
    }
    if (peripheralId != null) {
      _knownDevices.remove(peripheralId);
      onDevicesUpdated(_knownDevices.values.toList());
    }
  }

  Future<void> dispose() async {
    for (var sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _peripheralManager.stopAdvertising();
    await _centralManager.stopDiscovery();
  }
}
