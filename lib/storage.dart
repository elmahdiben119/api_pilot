import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// String key/value persistence used by the store. Lets tests swap in
/// [MemoryStorage] and lets old unencrypted data be migrated.
abstract interface class KeyValueStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Encrypted at rest (AES-GCM, key protected by the Android Keystore).
class SecureStorage implements KeyValueStorage {
  // resetOnError: false so a decryption problem surfaces as an error
  // instead of the plugin silently erasing everything.
  static const _s = FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: false));

  const SecureStorage();

  @override
  Future<String?> read(String key) => _s.read(key: key);

  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

/// Plain SharedPreferences, where versions before 1.1 kept everything.
/// Only read to migrate that data into [SecureStorage].
class PrefsStorage implements KeyValueStorage {
  const PrefsStorage();

  @override
  Future<String?> read(String key) async => (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  @override
  Future<void> delete(String key) async => (await SharedPreferences.getInstance()).remove(key);
}

class MemoryStorage implements KeyValueStorage {
  final Map<String, String> data;
  MemoryStorage([Map<String, String>? initial]) : data = {...?initial};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}
