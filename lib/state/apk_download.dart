import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'update_check.dart';

/// 下载为什么失败：决定提示用户检查网络、重新下载还是检查存储空间。
enum ApkDownloadFailure { network, incomplete, storage }

class ApkDownloadException implements Exception {
  const ApkDownloadException(this.reason);

  final ApkDownloadFailure reason;
}

class ApkDownloadCancelled implements Exception {
  const ApkDownloadCancelled();
}

/// 前台流式下载，不把整个 APK 放进内存；关闭下载窗口就取消请求。
class ApkDownloader {
  HttpClient? _client;
  bool _cancelled = false;
  bool _running = false;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<File> download(
    ReleaseApk apk,
    Directory directory, {
    void Function(int received)? onProgress,
  }) async {
    if (_running) {
      throw const ApkDownloadException(ApkDownloadFailure.network);
    }
    _running = true;
    _cancelled = false;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    _client = client;
    File? file;
    IOSink? sink;
    var complete = false;
    try {
      final request = await client
          .getUrl(apk.url)
          .timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.userAgentHeader, 'YCode-Android');
      // 对下载长度和摘要按 APK 原始字节校验，不接受透明解压。
      client.autoUncompress = false;
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (_cancelled) throw const ApkDownloadCancelled();
      if (response.statusCode != HttpStatus.ok) {
        throw const ApkDownloadException(ApkDownloadFailure.network);
      }
      if (response.contentLength >= 0 && response.contentLength != apk.size) {
        throw const ApkDownloadException(ApkDownloadFailure.incomplete);
      }
      await directory.create(recursive: true);
      // 固定文件名：每次下载覆盖上一份，缓存里不会越积越多。
      file = File('${directory.path}/ycode-update.apk.part');
      sink = file.openWrite();
      var received = 0;
      await for (final bytes in response.timeout(const Duration(seconds: 30))) {
        if (_cancelled) throw const ApkDownloadCancelled();
        received += bytes.length;
        if (received > apk.size) {
          throw const ApkDownloadException(ApkDownloadFailure.incomplete);
        }
        sink.add(bytes);
        // 等待磁盘写入，避免慢磁盘时积压整个安装包。
        await sink.flush();
        onProgress?.call(received);
      }
      await sink.close();
      sink = null;
      if (_cancelled) throw const ApkDownloadCancelled();
      if (received != apk.size) {
        throw const ApkDownloadException(ApkDownloadFailure.incomplete);
      }
      if (apk.sha256 != null) {
        final digest = await sha256.bind(file.openRead()).first;
        if (digest.toString() != apk.sha256) {
          throw const ApkDownloadException(ApkDownloadFailure.incomplete);
        }
      }
      if (_cancelled) throw const ApkDownloadCancelled();
      final verified = await file.rename('${directory.path}/ycode-update.apk');
      complete = true;
      return verified;
    } on ApkDownloadException {
      if (_cancelled) throw const ApkDownloadCancelled();
      rethrow;
    } on FileSystemException {
      if (_cancelled) throw const ApkDownloadCancelled();
      throw const ApkDownloadException(ApkDownloadFailure.storage);
    } on Object {
      // 连接、超时、TLS 和读取响应时的错误都算网络问题。
      if (_cancelled) throw const ApkDownloadCancelled();
      throw const ApkDownloadException(ApkDownloadFailure.network);
    } finally {
      client.close(force: true);
      _client = null;
      _running = false;
      try {
        // 写入已经失败时关闭会再报一次同样的错，不能盖掉上面的失败原因。
        if (sink != null) await sink.close().catchError((Object _) {});
      } finally {
        // 仅清理由本次失败或取消产生的半包，不清理其他下载或用户文件。
        if (!complete && file != null && await file.exists()) {
          await file.delete();
        }
      }
    }
  }
}

class AndroidUpdateInstaller {
  const AndroidUpdateInstaller();
  static const _channel = MethodChannel('local.baocode.mobile/platform');

  Future<Directory> directory() async {
    final path = await _channel.invokeMethod<String>('updateDirectory');
    if (path == null || path.isEmpty) {
      throw const ApkDownloadException(ApkDownloadFailure.storage);
    }
    return Directory(path);
  }

  /// false 表示已打开安装来源授权页，返回应用后需要再点一次安装。
  Future<bool> install(File file, ReleaseInfo release) async =>
      await _channel.invokeMethod<bool>('installUpdate', {
        'path': file.path,
        'version': release.version,
        'size': release.apk!.size,
        'sha256': release.apk!.sha256,
      }) ??
      false;
}
