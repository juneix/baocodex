import 'dart:async';
import 'dart:io';

import '../state/app_state.dart';
import '../models/user_facing_error.dart';

typedef DesktopAddressLookup = Future<List<InternetAddress>> Function(
  String host,
);

class AddressResolutionException implements Exception {
  const AddressResolutionException();
  @override
  String toString() => AppState.phrase(
    '无法解析连接地址，请检查域名和 DNS',
    'Cannot resolve the desktop address. Check the hostname and DNS.',
  );
}

class DesktopAddress {
  const DesktopAddress._(this.host, this.port, this.ip);
  final String host;
  final int port;
  final InternetAddress? ip;

  static DesktopAddress parse(String text) {
    final invalid = UserFacingError(
      AppState.phrase(
        '请输入域名或 IP:端口，IPv6 用 [地址]:端口',
        'Enter a host or IP with a port; use [address]:port for IPv6',
      ),
    );
    final uri = Uri.tryParse('udp://${text.trim()}');
    if (uri == null ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.path.isNotEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw invalid;
    }
    final host = uri.host.replaceAll('[', '').replaceAll(']', '').toLowerCase();
    final ip = InternetAddress.tryParse(host);
    if (ip == null) {
      final domain = host.endsWith('.')
          ? host.substring(0, host.length - 1)
          : host;
      final label = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
      if (domain.isEmpty ||
          domain.length > 253 ||
          RegExp(r'^[0-9.]+$').hasMatch(domain) ||
          !domain.split('.').every(label.hasMatch)) {
        throw invalid;
      }
    }
    return DesktopAddress._(host, uri.port, ip);
  }

  String get normalized => ip?.type == InternetAddressType.IPv6
      ? '[${ip!.address}]:$port'
      : '${ip?.address ?? host}:$port';
}

/// 保存域名，拨号时才解析。已知 IP 不访问 DNS，单个坏域名不阻断其他地址。
Future<List<String>> resolveDesktopAddresses(
  List<String> addresses, {
  DesktopAddressLookup lookup = InternetAddress.lookup,
  Duration timeout = const Duration(seconds: 3),
  bool allowEmpty = false,
}) async {
  final batches = await Future.wait([
    for (final text in addresses)
      () async {
        try {
          final address = DesktopAddress.parse(text);
          if (address.ip != null) return [address.normalized];
          final resolved = await lookup(address.host).timeout(timeout);
          return [
            for (final ip in resolved)
              ip.type == InternetAddressType.IPv6
                  ? '[${ip.address}]:${address.port}'
                  : '${ip.address}:${address.port}',
          ];
        } on SocketException {
          return <String>[];
        } on TimeoutException {
          return <String>[];
        } on UserFacingError {
          return <String>[];
        }
      }(),
  ]);
  final resolved = {for (final batch in batches) ...batch}.toList();
  if (addresses.isNotEmpty && resolved.isEmpty && !allowEmpty) {
    throw const AddressResolutionException();
  }
  return resolved;
}
