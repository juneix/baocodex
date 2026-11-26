import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/services.dart';

import '../models/user_facing_error.dart';
import 'app_state.dart';

typedef UploadRequest = Future<Object?> Function(
  String desktop,
  String method, [
  Map<String, Object?> params,
]);

/// 系统选择器只返回用户选择的文件名和原始字节，不向电脑发送手机 URI。
class UploadFile {
  const UploadFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

class UploadSelectionFailure extends UserFacingError {
  const UploadSelectionFailure(super.message, this.name, this.size);
  final String name;
  final int size;
}

class UploadUnconfirmed extends UserFacingError {
  const UploadUnconfirmed(super.message);
}

const _platform = MethodChannel('local.baocode.mobile/platform');

Future<UploadFile?> pickUploadFile(AppState state) async {
  try {
    final result = await _platform.invokeMapMethod<String, Object?>(
      'pickUploadFile',
    );
    if (result == null) return null;
    final name = result['name'], bytes = result['bytes'];
    if (name is! String || name.isEmpty || bytes is! Uint8List) {
      throw const FormatException();
    }
    if (bytes.length > LinkLimits.upload) {
      throw UploadSelectionFailure(_tooLarge(state).message, name, bytes.length);
    }
    return UploadFile(name, bytes);
  } on PlatformException catch (error) {
    if (error.code == 'upload_too_large') throw _tooLarge(state);
    throw UserFacingError(
      state.tr(
        '无法读取所选文件，请重新选择。',
        'Could not read the selected file. Please select it again.',
      ),
    );
  }
}

UserFacingError _tooLarge(AppState state) => UserFacingError(
  state.tr('单个文件不能超过 8 MiB。', 'Each file must be no larger than 8 MiB.'),
);

/// 只发一次：断线或超时后电脑可能已经写入文件，不能自动重试。
Future<String> uploadFile(
  AppState state, {
  required String desktop,
  required UploadFile file,
  String? project,
  String? bot,
  UploadRequest? request,
}) async {
  if (file.bytes.length > LinkLimits.upload) throw _tooLarge(state);
  if (bot == null && project == null) {
    throw UserFacingError(
      state.tr(
        '当前对话没有可上传文件的目标。',
        'This conversation has no file upload target.',
      ),
    );
  }
  try {
    final result = await (request ?? state.request)(
      desktop,
      LinkMethods.upload,
      {
        if (bot != null) 'bot': bot else 'project': project,
        'name': file.name,
        'data': base64Encode(file.bytes),
      },
    );
    if (result is Map && result['tooLarge'] == true) throw _tooLarge(state);
    final path = result is Map ? result['path'] : null;
    if (path is! String ||
        !isHostAbsolutePath(path) ||
        path.contains(RegExp(r'[\x00-\x1f\x7f"]'))) {
      throw UploadUnconfirmed(
        state.tr(
          '上传未确认：电脑没有返回可引用的文件路径。草稿已保留。',
          'Upload unconfirmed: the desktop did not return a usable file path. Draft kept.',
        ),
      );
    }
    // 不规范化：电脑可能把文件写在 SSH 主机上，而非手机或本机。
    return path;
  } on LinkRemoteException catch (error) {
    if (error.code == LinkErrors.unknown ||
        error.code == LinkErrors.unsupported) {
      throw UserFacingError(
        state.tr(
          '此电脑不支持文件上传，请更新。',
          'This desktop does not support file uploads. Please update it.',
        ),
      );
    }
    rethrow;
  } on TimeoutException {
    throw _unconfirmed(state);
  } on LinkClosedException {
    throw _unconfirmed(state);
  }
}

UploadUnconfirmed _unconfirmed(AppState state) => UploadUnconfirmed(
  state.tr(
    '上传未确认，电脑可能已收到文件。草稿已保留，请检查连接；不会自动重试。',
    'Upload unconfirmed; the desktop may have received the file. Draft kept. Check the connection; no automatic retry.',
  ),
);

bool isHostAbsolutePath(String path) =>
    path.startsWith('/') ||
    path.startsWith(r'\\') ||
    RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path);

final _plainFilePath = RegExp(r'^[A-Za-z0-9_./\\:~+\-]+$');

bool _sentenceEnd(String character) => character == '.' || character == ':';
bool _directoryEnd(String path) => path.endsWith('/') || path.endsWith(r'\');

/// 与电脑的 @ 文件引用约定一致；路径本身始终原样保留。
String fileMentionText(String path) {
  final plain =
      _plainFilePath.hasMatch(path) &&
      !_sentenceEnd(path.substring(path.length - 1));
  return plain ? '@$path' : '@"$path"';
}

/// 在指定 @ 处读取完整 token：引号内允许空格和中文，未加引号时句末 . : 不属路径。
/// 返回 token 的结束位置，扫描下一项时不会误读引号内的 @。
({String path, bool directory, int end})? parseFileMention(
  String text,
  int at,
) {
  if (at < 0 || at >= text.length || text[at] != '@') return null;
  final start = at + 1;
  var end = start;
  String path;
  if (start < text.length && text[start] == '"') {
    final close = text.indexOf('"', start + 1);
    if (close < 0) return null;
    path = text.substring(start + 1, close);
    if (path.contains('\n') || path.contains('\r')) return null;
    end = close + 1;
  } else {
    while (end < text.length && _plainFilePath.hasMatch(text[end])) {
      end++;
    }
    while (end > start && _sentenceEnd(text[end - 1])) {
      end--;
    }
    path = text.substring(start, end);
    if (!path.contains('/') && !path.contains(r'\') && !path.contains('.')) {
      return null;
    }
  }
  final directory = _directoryEnd(path);
  if (directory) path = path.substring(0, path.length - 1);
  if (path.isEmpty) return null;
  return (path: path, directory: directory, end: end);
}

Iterable<({String path, bool directory, int end})> _fileMentions(
  String text,
) sync* {
  var offset = 0;
  while (offset < text.length) {
    final at = text.indexOf('@', offset);
    if (at < 0) return;
    final mention = parseFileMention(text, at);
    if (mention != null) yield mention;
    offset = mention?.end ?? at + 1;
  }
}

/// 仅显示末尾独立的 @绝对文件引用区；行内引用、缩进代码和代码围栏不改。
/// 返回值只供展示，复制和编辑始终使用原始正文。
({String body, List<String> paths}) fileReferenceRegion(String text) {
  final lines = text.split('\n');
  final candidates = <int, String>{};
  String? fence;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final marker = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(line)?.group(1);
    if (marker != null) {
      if (fence == null) {
        fence = marker;
      } else if (marker[0] == fence[0] && marker.length >= fence.length) {
        fence = null;
      }
      continue;
    }
    if (fence != null || line.startsWith('    ') || line.startsWith('\t')) {
      continue;
    }
    final trimmed = line.trim();
    final ref = parseFileMention(trimmed, 0);
    if (ref != null &&
        ref.end == trimmed.length &&
        !ref.directory &&
        isHostAbsolutePath(ref.path)) {
      candidates[i] = ref.path;
    }
  }
  var end = lines.length - 1;
  while (end >= 0 && lines[end].trim().isEmpty) {
    end--;
  }
  final paths = <String>[];
  while (end >= 0 && candidates.containsKey(end)) {
    paths.insert(0, candidates[end]!);
    end--;
  }
  if (paths.isEmpty) return (body: text, paths: const []);
  return (body: lines.take(end + 1).join('\n').trimRight(), paths: paths);
}

String fileReferenceName(String path) => path.split(RegExp(r'[/\\]')).last;

bool hasFileMention(String text, String path) =>
    _fileMentions(text).any((mention) => mention.path == path);

/// 历史只回显文本，不带结构化 mentions；编辑与发送使用同一解析规则。
Set<String> absoluteFileMentions(String text) => {
  for (final mention in _fileMentions(text))
    if (isHostAbsolutePath(mention.path)) mention.path,
};
