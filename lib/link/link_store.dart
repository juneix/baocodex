import 'package:flutter/services.dart';

abstract interface class LinkStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class MemoryLinkStore implements LinkStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}

/// The native implementation must use the OS credential store, not preferences.
class PlatformLinkStore implements LinkStore {
  static const _channel = MethodChannel('local.baocode.mobile/platform');

  @override
  Future<String?> read(String key) =>
      _channel.invokeMethod<String>('secureRead', {'key': key});

  @override
  Future<void> write(String key, String value) =>
      _channel.invokeMethod<void>('secureWrite', {'key': key, 'value': value});

  @override
  Future<void> remove(String key) =>
      _channel.invokeMethod<void>('secureRemove', {'key': key});
}
