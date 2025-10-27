import 'package:uwb/flutter_uwb.dart';

sealed class DiscoveryDeviceState {
  final UwbDevice device;
  const DiscoveryDeviceState(this.device);
}

class DeviceFoundState extends DiscoveryDeviceState {
  const DeviceFoundState(super.device);
}

class DeviceLostState extends DiscoveryDeviceState {
  const DeviceLostState(super.device);
}

class DeviceConnectedState extends DiscoveryDeviceState {
  const DeviceConnectedState(super.device);
}

class DeviceDisconnectedState extends DiscoveryDeviceState {
  const DeviceDisconnectedState(super.device);
}

class DeviceInvitedState extends DiscoveryDeviceState {
  const DeviceInvitedState(super.device);
}

class DeviceInviteRejected extends DiscoveryDeviceState {
  const DeviceInviteRejected(super.device);
}

/// Represents the state of a UWB session
sealed class UwbSessionState {
  final UwbDevice device;
  const UwbSessionState(this.device);
}

class UwbSessionStartedState extends UwbSessionState {
  const UwbSessionStartedState(super.device);
}

class UwbSessionDisconnectedState extends UwbSessionState {
  const UwbSessionDisconnectedState(super.device);
}
