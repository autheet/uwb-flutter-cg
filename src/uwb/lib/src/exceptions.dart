import 'package:uwb/flutter_uwb.dart';

class UwbException implements Exception {
  final ErrorCode code;
  final String? message;

  UwbException(this.code, this.message);

  @override
  String toString() => "($code) $message";
}
