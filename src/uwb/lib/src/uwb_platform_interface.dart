import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:uwb/flutter_uwb.dart';
import 'package:uwb/src/uwb.g.dart';
import 'package:uwb/src/states.dart';

abstract class UwbPlatform extends PlatformInterface {
  UwbPlatform() : super(token: _token);

  static final Object _token = Object();

  static UwbPlatform _instance = Uwb();

  static UwbPlatform get instance => _instance;

  static set instance(UwbPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Stream<UwbSessionState> get uwbSessionStateStream {
    throw UnimplementedError('uwbSessionStateStream has not been implemented.');
  }

  Stream<List<UwbDevice>> get uwbDataStream {
    throw UnimplementedError('uwbDataStream has not been implemented.');
  }
  
  Future<void> startRanging(Uint8List peerAddress, UwbSessionConfig config) {
    throw UnimplementedError('startRanging() has not been implemented.');
  }

  Future<bool> isUwbSupported() {
    throw UnimplementedError('isUwbSupported() has not been implemented.');
  }

  Future<void> stopRanging(String peerAddress) {
    throw UnimplementedError('stopRanging() has not been implemented.');
  }

  Future<void> stopUwbSessions() {
    throw UnimplementedError('stopUwbSessions() has not been implemented.');
  }

  Future<Uint8List> getLocalUwbAddress() {
    throw UnimplementedError('getLocalUwbAddress() has not been implemented.');
  }
}
