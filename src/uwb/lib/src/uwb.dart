import 'dart:async';
import 'dart:convert';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:uwb/src/uwb_ble_manager.dart';
import 'package:uwb/src/uuid_generator.dart';
import 'package:flutter/services.dart';
import 'package:uwb/flutter_uwb.dart';
import 'package:uwb/src/uwb_platform_interface.dart';

// UWB Instance for Plugin, managing both BLE and UWB
class Uwb extends UwbPlatform {
  /// Returns a list of all discovered devices
  /// This list is updated whenever a new device is discovered, lost, connected
  /// or disconnected.
  Stream<Iterable<UwbDevice>> get discoveredDevicesStream =>
      _discoveredDevicesStream.stream.asBroadcastStream();

  /// Notifies about the current state of the discovery process
  Stream<DiscoveryDeviceState> get discoveryStateStream =>
      _discoveryStateStream.stream.asBroadcastStream();

  Stream<Iterable<UwbDevice>> get rangingDevicesStream =>
      _rangingDevicesStream.stream.asBroadcastStream();

  Stream<UwbSessionState> get uwbSessionStateStream =>
      _uwbSessionStateStream.stream.asBroadcastStream();

  /// Returns a list of all current ranging devices
  Stream<Iterable<UwbDevice>> get uwbDataStream {
    return _uwbDataChannel.receiveBroadcastStream().map(
      (data) {
        var device = _parseUwbData(data);
        _rangingDevices[device.id] = device;
        return _rangingDevices.values.toList();
      },
    ).asBroadcastStream();
  }

  final _discoveryStateStream =
      StreamController<DiscoveryDeviceState>.broadcast();
  final _discoveredDevicesStream =
      StreamController<Iterable<UwbDevice>>.broadcast();

  final _uwbSessionStateStream = StreamController<UwbSessionState>.broadcast();
  final _rangingDevicesStream =
      StreamController<Iterable<UwbDevice>>.broadcast();

  final _rangingDevices = <String, UwbDevice>{};
  final _discoveredDevices = <String, UwbDevice>{};

  // Stream Channels Setup
  final UwbHostApi _hostApi = UwbHostApi();
  // The _uwbDataChannel is removed as ranging results will come via Pigeon
  // final EventChannel _uwbDataChannel = const EventChannel('uwb_plugin/uwbData');
  late UwbFlutterApiHandler _flutterApiHandler;
  late UwbBleManager _bleManager;
  final Map<String, DiscoveredPeer> _discoveredBlePeers = {};
  // Assume authenticatingDeviceName is available as a class member
  String? _authenticatingDeviceName;
  String? _auHourlyDigest;

  Uwb({String? authenticatingDeviceName}) : _authenticatingDeviceName = authenticatingDeviceName {
    // Setup UWB API Handler
    _flutterApiHandler = UwbFlutterApiHandler(
      onDiscoveryDeviceFound: _onDiscoveryDeviceFound,
      onDiscoveryDeviceLost: _onDiscoveryDeviceLost,
      onDiscoveryDeviceConnected: _onDiscoveryDeviceConnected, // Keep native callbacks for now
      onDiscoveryDeviceDisconnected: _onDiscoveryDeviceDisconnected, // Keep native callbacks for now
      onDiscoveryDeviceRejected: _onDiscoveryDeviceRejected,
      onDiscoveryConnectionRequestReceived:
          _onDiscoveryConnectionRequestReceived,
      // We might need to introduce new callbacks or modify existing ones
      // to handle BLE-specific handshake events and trigger native UWB ranging.
      // For now, I'll keep the existing UWB session callbacks.
      // onUwbSessionStarted: _onUwbSessionStarted,
      onPermissionRequired: _onPermissionRequired,
      onUwbSessionStarted: _onUwbSessionStarted,
      onUwbSessionDisconnected: _onUwbSessionDisconnected,
    );

    UwbFlutterApi.setup(_flutterApiHandler);

    // Initialize BLE Manager later in discoverDevices when digest is available
  }

  void _initializeBleManager() {
    // Derive UUIDs using auHourlyDigest
    final serviceUuid = generateUuid(Uint8List.fromList(utf8.encode(_auHourlyDigest!)), 'uwb_service');
    final handshakeCharacteristicUuid = generateUuid(Uint8List.fromList(utf8.encode(_auHourlyDigest!)), 'uwb_handshake');
    final platformCharacteristicUuid = generateUuid(Uint8List.fromList(utf8.encode(_auHourlyDigest!)), 'uwb_platform');
    _bleManager = UwbBleManager(
    // Listen to BLE discovery streams
    _bleManager.peerDiscoveredStream.listen(_onBlePeerDiscovered);
    _bleManager.peerLostStream.listen(_onBlePeerLost);
    _bleManager.bleDataReceivedStream.listen(_onBleDataReceived);
  }

  void _onBlePeerDiscovered(DiscoveredPeer peer) {
    // Check if the device is already discovered via native methods
    if (_discoveredDevices.containsKey(peer.peripheral.uuid.toString())) {
      return; // Device already in the list, probably from native discovery
    }
    final uwbDevice = UwbDevice(
        uwbData: null, // UWB data is not available at BLE discovery stage
        id: peer.peripheral.uuid.toString(), name: peer.deviceName, deviceType: _mapPlatformToDeviceType(peer.platform), state: DeviceState.found, rssi: peer.rssi);
    _onDiscoveryDeviceFound(uwbDevice);
  }

  int maxConnections = -1;

  void _onDiscoveryDeviceFound(UwbDevice device) {
    if (!_discoveredDevices.containsKey(device.id)) {
      _discoveredDevices[device.id] = device;
      _discoveredDevicesStream.add(_discoveredDevices.values);

      _discoveryStateStream.add(
        DeviceFoundState(device),
      );
    }
  }

  void _onDiscoveryDeviceLost(UwbDevice device) {
    _discoveredDevices.remove(device.id);
    _discoveredDevicesStream.add(_discoveredDevices.values);

    _discoveryStateStream.add(
      DeviceLostState(device),
    );
  }

  void _onBlePeerLost(DiscoveredPeer peer) {
     final uwbDevice = UwbDevice(id: peer.peripheral.uuid.toString(), name: peer.deviceName, deviceType: _mapPlatformToDeviceType(peer.platform), state: DeviceState.lost, uwbData: null);
     _onDiscoveryDeviceLost(uwbDevice);
  }

  void _onDiscoveryDeviceConnected(UwbDevice device) {
    if (_discoveredDevices.containsKey(device.id)) {
      _discoveredDevices[device.id] = device;
      _discoveredDevicesStream.add(_discoveredDevices.values);
    }

    _discoveryStateStream.add(
      DeviceConnectedState(device),
    );
  }

  void _onDiscoveryDeviceDisconnected(UwbDevice device) {
    if (_discoveredDevices.containsKey(device.id)) {
      _discoveredDevices[device.id] = device;
      _discoveredDevicesStream.add(_discoveredDevices.values);
    }

    _discoveryStateStream.add(
      DeviceDisconnectedState(device),
    );
  }

  void _onDiscoveryDeviceRejected(UwbDevice device) {
    _discoveryStateStream.add(DeviceInviteRejected(device));
  }

  void _onBleDataReceived(BleDataReceived data) {
     // Handle received BLE handshake data here. This data can be used to
     // exchange UWB configuration parameters for the ranging session.
  }

  void _onDiscoveryConnectionRequestReceived(UwbDevice device) {
    _discoveryStateStream.add(DeviceInvitedState(device));
  }

  void _onPermissionRequired(PermissionAction action) {}

  void _onUwbSessionStarted(UwbDevice device) {
    _rangingDevices[device.id] = device;
    _rangingDevicesStream.add(_rangingDevices.values);

    // Update the discovered devices list if still connected
    if (_discoveredDevices.containsKey(device.id)) {
      _discoveredDevices[device.id] = device;
      _discoveredDevicesStream.add(_discoveredDevices.values);
    }

    _uwbSessionStateStream.add(
      UwbSessionStartedState(device),
    );
  }

  void _onUwbSessionDisconnected(UwbDevice device) {
    // TODO: Check if device is still connected via OOB
    _discoveredDevices[device.id] = device;
    _discoveredDevicesStream.add(_discoveredDevices.values);

    _rangingDevices.remove(device.id);
    _rangingDevicesStream.add(_rangingDevices.values);

    _uwbSessionStateStream.add(
      UwbSessionDisconnectedState(device),
    );
  }

  /// Discover nearby devices
  /// [displayName] is the name of the device that will be shown to other devices
  /// [auHourlyDigest] is used to derive the BLE UUIDs for discovery and handshake.
  @override
 Future<void> discoverDevices(String deviceName, String auHourlyDigest) async {
    _authenticatingDeviceName = deviceName;
    _auHourlyDigest = auHourlyDigest;

    _initializeBleManager();
    // Use BLE manager for discovery
 await _bleManager.start();
  }

  @override
  Future<void> stopDiscovery() async {
    // Use BLE manager to stop discovery
    _discoveredDevices
        .removeWhere((key, value) => value.state != DeviceState.connected);
    _discoveredDevicesStream.add(_discoveredDevices.values);

    await _bleManager.stopDiscovery();
    // Stop native discovery if it was started - this depends on native implementation
    return await _hostApi.stopDiscovery();
  }

  /// Stops the UWB session with the device
  /// [device] is the device to stop the session with
  @override
  Future<void> stopRanging(UwbDevice device) async {
    try {
      if (!_discoveredDevices.containsKey(device.id)) {
        _discoveredDevices.remove(device.id);
        _discoveredDevicesStream.add(_discoveredDevices.values);
      }

      await _hostApi.stopRanging(device);

      if (_rangingDevices.containsKey(device.id)) {
        _rangingDevices.remove(device.id);
        _rangingDevicesStream.add(_rangingDevices.values);

        _uwbSessionStateStream.add(
          UwbSessionDisconnectedState(device),
        );
      }
    } on PlatformException catch (e) {
      return await Future.error(e);
    }
  }

  @override
  Future<void> stopUwbSessions() async {
    try {
      _rangingDevices.clear();
      return await _hostApi.stopUwbSessions();
    } on PlatformException catch (e) {
      return Future.error(e);
    }
  }

  /// Whether the device supports UWB or not
  @override
  Future<bool> isUwbSupported() async {
    return await _hostApi.isUwbSupported();
  }

  /// Connects to a device and starts ranging
  /// [device] is the device to connect to
  @override
  Future<void> startRanging(UwbDevice device) async {
    // This method is called after a device is discovered via BLE and
    // potentially after a BLE handshake. Now, initiate the native UWB ranging session.
     try {
      return await _hostApi.startRanging(device);
    } on PlatformException catch (e) {
      _parsePlatformException(e);
    }
  }

  /// Accepts or rejects a connection request from a device
  /// Use this method after receiving a [DeviceInvitedState]
  /// from the [discoveryStateStream].
  /// [device] is the device to accept or reject the connection request from
  @override
  Future<void> handleConnectionRequest(UwbDevice device, bool accept) async {
    // This method is called after a connection request is received (likely via BLE handshake).
    // Handle the request and initiate native UWB ranging if accepted.
     try {
      return await _hostApi.handleConnectionRequest(device, accept);
    } on PlatformException catch (e) {
      _parsePlatformException(e);
    }
  }

  void dispose() {
    _bleManager.dispose();
  }
  
  DeviceType _mapPlatformToDeviceType(String platform) {
    return platform.toLowerCase() == 'android' ? DeviceType.controller : DeviceType.iosdevice; // Basic mapping
  }
  void _parsePlatformException(PlatformException e) {
    throw UwbException(ErrorCode.values[int.parse(e.code)], e.message);
  }

  UwbDevice _parseUwbData(String data) {
    Map<String, dynamic> jsonData = jsonDecode(data.toString());
    String id = jsonData['id'].toString();
    String name = jsonData['name'].toString();

    // Available: Apple API
    Direction3D? direction;
    if (jsonData['directionX'] != null &&
        jsonData['directionY'] != null &&
        jsonData['directionZ'] != null) {
      direction = Direction3D(
        x: jsonData['directionX'],
        y: jsonData['directionY'],
        z: jsonData['directionZ'],
      );
    }

    // Available: Android and Apple API
    double? distance;
    if (jsonData['distance'] != null) {
      distance = double.tryParse(
        jsonData['distance'].toString(),
      );
    }

    // Available: Android API and Apple Accessory API
    double? azimuth;
    if (jsonData['azimuth'] != null) {
      azimuth = double.tryParse(
        jsonData['azimuth'].toString(),
      );
    }

    // Available: Android API and Apple Accessory API
    double? elevation;
    if (jsonData['elevation'] != null) {
      elevation = double.tryParse(
        jsonData['elevation'].toString(),
      );
    }

    // Available: Apple API
    double? horizontalAngle;
    if (jsonData['horizontalAngle'] != null) {
      horizontalAngle = double.tryParse(
        jsonData['horizontalAngle'].toString(),
      );
    }

    // convert elevation and azimuth to direction
    // check if direction is null
    /*if (azimuth != null && elevation != null) {
      //direction = Math.toDirection3D(azimuth, elevation);
      var angle = azimuth * (pi / 180.0);
      var x = distance! * sin(angle);
      var y = distance * cos(angle);
      direction = Direction3D(x: x, y: y, z: 0);
    }*/

    DeviceType deviceType = DeviceType.smartphone;
    if (jsonData['deviceType'] != null) {
      deviceType = DeviceType.values[jsonData['deviceType']];
    }

    return UwbDevice(
      id: id,
      name: name,
      uwbData: UwbData(
        distance: distance,

        azimuth: azimuth,
        elevation: elevation,
        direction: direction,
        horizontalAngle: horizontalAngle,
      ),
      deviceType: deviceType,
    );
  }

}
