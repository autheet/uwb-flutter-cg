import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Generates a UUID string based on a digest and a purpose string.
///
/// The function computes the SHA-256 hash of the concatenated `digest` and
/// `purpose` strings and uses the first 16 bytes of the hash to generate
/// a version 5 UUID.
///
/// Args:
///   digest: A string representing the digest (e.g., hourly digest).
///   purpose: A string describing the purpose of the UUID (e.g., 'uwb_service').
///
/// Returns:
///   A valid UUID string.
String generateUuid(String digest, String purpose) {
  final input = utf8.encode(digest + purpose);
  final hash = sha256.convert(input).bytes;

  // Use the first 16 bytes of the SHA-256 hash to generate a UUID.
  // SHA-256 produces 32 bytes, UUIDs are 16 bytes.
  final uuidBytes = hash.sublist(0, 16);

  // Format the first 16 bytes into a standard UUID string (8-4-4-4-12).
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(uuidBytes[i].toRadixString(16).padLeft(2, '0'));
    if (i == 3 || i == 5 || i == 7 || i == 9) {
      buffer.write('-');
    }
  }
  // Ensure the UUID is lowercase
  return buffer.toString().toLowerCase();
}