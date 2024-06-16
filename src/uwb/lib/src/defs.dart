import 'package:uwb/src/uwb.g.dart';

// System Callbacks
typedef OnPermissionRequired = void Function(PermissionAction action);

// Type Definitions for OOB Discovery Callbacks
typedef OnDiscoveryDeviceState = void Function(
    UwbDevice device, DeviceState status);
typedef OnDiscoveryDeviceFound = void Function(UwbDevice device);
typedef OnDiscoveryDeviceLost = void Function(UwbDevice device);
typedef OnDiscoveryDeviceConnected = void Function(UwbDevice device);
typedef OnDiscoveryDeviceDisconnected = void Function(UwbDevice device);
typedef OnDiscoveryDeviceRejected = void Function(UwbDevice device);
typedef OnDiscoveryConnectionRequestReceived = void Function(UwbDevice device);

// Type Definitions for UWB Ranging Callbacks
typedef OnUwbSessionStarted = void Function(UwbDevice device);
typedef OnUwbSessionDisconnected = void Function(UwbDevice device);
