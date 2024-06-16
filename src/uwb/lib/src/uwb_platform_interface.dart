import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:uwb/flutter_uwb.dart';

class UwbFlutterApiHandler extends UwbFlutterApi {
  final OnDiscoveryDeviceFound onDiscoveryDeviceFound;
  final OnDiscoveryDeviceLost onDiscoveryDeviceLost;
  final OnDiscoveryDeviceConnected onDiscoveryDeviceConnected;
  final OnDiscoveryDeviceDisconnected onDiscoveryDeviceDisconnected;
  final OnDiscoveryDeviceRejected onDiscoveryDeviceRejected;
  final OnDiscoveryConnectionRequestReceived
      onDiscoveryConnectionRequestReceived;
  final OnPermissionRequired onPermissionRequired;
  final OnUwbSessionStarted onUwbSessionStarted;
  final OnUwbSessionDisconnected onUwbSessionDisconnected;

  UwbFlutterApiHandler({
    required this.onDiscoveryDeviceFound,
    required this.onDiscoveryDeviceLost,
    required this.onDiscoveryDeviceConnected,
    required this.onDiscoveryDeviceDisconnected,
    required this.onDiscoveryDeviceRejected,
    required this.onDiscoveryConnectionRequestReceived,
    required this.onPermissionRequired,
    required this.onUwbSessionStarted,
    required this.onUwbSessionDisconnected,
  });

  @override
  void onHostDiscoveryDeviceConnected(UwbDevice device) {
    onDiscoveryDeviceConnected(device);
  }

  @override
  void onHostDiscoveryDeviceDisconnected(UwbDevice device) {
    onDiscoveryDeviceDisconnected(device);
  }

  @override
  void onHostDiscoveryDeviceFound(UwbDevice device) {
    onDiscoveryDeviceFound(device);
  }

  @override
  void onHostDiscoveryConnectionRequestReceived(UwbDevice device) {
    onDiscoveryConnectionRequestReceived(device);
  }

  @override
  void onHostDiscoveryDeviceLost(UwbDevice device) {
    onDiscoveryDeviceLost(device);
  }

  @override
  void onHostDiscoveryDeviceRejected(UwbDevice device) {
    onDiscoveryDeviceRejected(device);
  }

  @override
  void onHostPermissionRequired(PermissionAction action) {
    onPermissionRequired(action);
  }

  @override
  void onHostUwbSessionDisconnected(UwbDevice device) {
    onUwbSessionDisconnected(device);
  }

  @override
  void onHostUwbSessionStarted(UwbDevice device) {
    onUwbSessionStarted(device);
  }
}

class UwbPlatform extends PlatformInterface implements UwbHostApi {
  UwbPlatform() : super(token: _token);

  static final Object _token = Object();

  static UwbPlatform _instance = Uwb();

  /// The default instance of [UwbPlatform] to use.
  ///
  /// Defaults to [MethodChannelUwb].
  static UwbPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [UwbPlatform] when
  /// they register themselves.
  static set instance(UwbPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  @override
  Future<void> startRanging(UwbDevice device) {
    throw UnimplementedError();
  }

  @override
  Future<bool> isUwbSupported() {
    throw UnimplementedError();
  }

  @override
  Future<void> stopDiscovery() {
    throw UnimplementedError();
  }

  @override
  Future<void> stopRanging(UwbDevice device) {
    throw UnimplementedError();
  }

  @override
  Future<void> stopUwbSessions() {
    throw UnimplementedError();
  }

  @override
  Future<void> handleConnectionRequest(UwbDevice device, bool accept) {
    throw UnimplementedError();
  }

  @override
  Future<void> discoverDevices(String deviceName) {
    throw UnimplementedError();
  }
}
