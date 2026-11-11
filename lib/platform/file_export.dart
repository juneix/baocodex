import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';

class DownloadTooLargeException implements Exception {
  const DownloadTooLargeException();

  @override
  String toString() => AppState.phrase(
    '文件超过手机下载上限（8 MiB）',
    'File exceeds the 8 MiB download limit',
  );
}

Uint8List decodeFileDownload(Object? response) {
  if (response is! Map) throw const FormatException('下载响应无效');
  if (response['tooLarge'] == true) throw const DownloadTooLargeException();
  final data = response['data'];
  if (data is! String) throw const FormatException('下载响应缺少文件数据');
  if (data.length > ((LinkLimits.download + 2) ~/ 3) * 4) {
    throw const DownloadTooLargeException();
  }
  final Uint8List bytes;
  try {
    bytes = base64Decode(data);
  } on FormatException {
    // Base64 解码异常可能带原始文件内容，不能直接回显到界面。
    throw FormatException(AppState.phrase('下载文件数据损坏', 'Invalid download data'));
  }
  if (bytes.length > LinkLimits.download) {
    throw const DownloadTooLargeException();
  }
  return bytes;
}

Future<bool> saveFile(String name, Uint8List bytes) async {
  if (name.trim().isEmpty ||
      name == '.' ||
      name == '..' ||
      name.contains(RegExp(r'[/\\\x00]'))) {
    throw const FormatException('保存文件名无效');
  }
  if (bytes.length > LinkLimits.download) {
    throw const DownloadTooLargeException();
  }
  final saved = await const MethodChannel('local.baocode.mobile/platform')
      .invokeMethod<bool>('saveFile', {'name': name, 'bytes': bytes});
  if (saved == null) throw const FormatException('未收到文件保存结果');
  return saved;
}
