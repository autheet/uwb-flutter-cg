import 'package:uwb/flutter_uwb.dart';

sealed class DiscoveryDeviceState {
  final UwbDevice device;
  const DiscoveryDeviceState(this.device);
}

class DeviceFoundState extends DiscoveryDeviceState {
  const DeviceFoundState(UwbDevice device) : super(device);
}

class DeviceLostState extends DiscoveryDeviceState {
  const DeviceLostState(UwbDevice device) : super(device);
}

class DeviceConnectedState extends DiscoveryDeviceState {
  const DeviceConnectedState(UwbDevice device) : super(device);
}

class DeviceDisconnectedState extends DiscoveryDeviceState {
  const DeviceDisconnectedState(UwbDevice device) : super(device);
}

class DeviceInvitedState extends DiscoveryDeviceState {
  const DeviceInvitedState(UwbDevice device) : super(device);
}

class DeviceInviteRejected extends DiscoveryDeviceState {
  const DeviceInviteRejected(UwbDevice device) : super(device);
}

/// Represents the state of a UWB session
sealed class UwbSessionState {
  final UwbDevice device;
  const UwbSessionState(this.device);
}

class UwbSessionStartedState extends UwbSessionState {
  const UwbSessionStartedState(UwbDevice device) : super(device);
}

class UwbSessionDisconnectedState extends UwbSessionState {
  const UwbSessionDisconnectedState(UwbDevice device) : super(device);
}
