import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';

import '../models/user_facing_error.dart';
import 'app_state.dart';

const projectUrl = 'https://github.com/shuishani/ycode';

/// 最新版本从 GitHub Releases 取：YCode 只在那里发布。
const updateReleaseApi =
    'https://api.github.com/repos/shuishani/ycode/releases/latest';

class ReleaseApk {
  const ReleaseApk({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
  });

  final String name;
  final Uri url;
  final int size;
  final String? sha256;
}

/// 一次检查最多等这么久，慢网络也不让按钮一直转。
const updateCheckTimeout = Duration(seconds: 10);

/// 读出 release 的 JSON 文本；测试里换成不联网的实现。
typedef ReleaseFetcher = Future<String> Function(Uri url);

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.notes,
    required this.url,
    this.apk,
  });

  final ReleaseApk? apk;

  /// 去掉 `v` 的标签，如 `0.2.0`。
  final String version;

  /// release 的说明正文，可能为空。
  final String notes;

  /// release 页面，在浏览器里打开。
  final String url;
}

class UpdateCheck {
  const UpdateCheck({
    required this.latest,
    required this.comparable,
    required this.newer,
  });

  final ReleaseInfo latest;

  /// 当前版本是不是可比较的数字版本；`dev` 不是。
  final bool comparable;

  final bool newer;
}

final _versionPattern = RegExp(r'^[vV]?(\d+)\.(\d+)\.(\d+)$');

/// `v0.2.0`、`0.2.0` → `0.2.0`；不是三段数字就是 null。
String? normalizeVersion(String text) {
  final match = _versionPattern.firstMatch(text.trim());
  if (match == null) return null;
  return '${int.parse(match[1]!)}.${int.parse(match[2]!)}.'
      '${int.parse(match[3]!)}';
}

/// 按 major.minor.patch 的数字比较；任一边不像版本号时返回 null。
int? compareVersions(String a, String b) {
  final left = normalizeVersion(a);
  final right = normalizeVersion(b);
  if (left == null || right == null) return null;
  final x = left.split('.').map(int.parse).toList();
  final y = right.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return 0;
}

/// GitHub 的 release JSON：标签、说明正文和页面地址。
ReleaseInfo parseRelease(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('release is not an object');
  }
  final tag = decoded['tag_name'];
  final url = decoded['html_url'];
  if (tag is! String || url is! String) {
    throw const FormatException('release has no tag or page');
  }
  final version = normalizeVersion(tag);
  final page = Uri.tryParse(url);
  if (version == null ||
      page == null ||
      page.scheme != 'https' ||
      page.host != 'github.com' ||
      page.userInfo.isNotEmpty ||
      page.hasPort ||
      !page.path.startsWith('/shuishani/ycode/releases/tag/')) {
    throw const FormatException('release is unreadable');
  }
  final notes = decoded['body'];
  return ReleaseInfo(
    version: version,
    notes: notes is String ? notes.trim() : '',
    url: url,
    apk: _releaseApk(decoded['assets'], tag),
  );
}

ReleaseApk? _releaseApk(Object? assets, String tag) {
  if (assets is! List) return null;
  final candidates = <ReleaseApk>[];
  for (final value in assets) {
    if (value is! Map<String, Object?>) continue;
    final name = value['name'];
    final url = value['browser_download_url'];
    final size = value['size'];
    if (name is! String || url is! String || size is! int || size <= 0) {
      continue;
    }
    final lower = name.toLowerCase();
    if (!RegExp(r'^ycode[-\w.]*\.apk$').hasMatch(lower) ||
        lower.contains('x86') ||
        lower.contains('armeabi') ||
        lower.contains('debug')) {
      continue;
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 6 ||
        uri.pathSegments.take(5).join('/') !=
            'shuishani/ycode/releases/download/$tag' ||
        !uri.pathSegments.last.toLowerCase().endsWith('.apk')) {
      continue;
    }
    final digest = value['digest'];
    String? sha256;
    if (digest != null) {
      if (digest is! String ||
          !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
        continue;
      }
      sha256 = digest.substring(7).toLowerCase();
    }
    candidates.add(
      ReleaseApk(name: name, url: uri, size: size, sha256: sha256),
    );
  }
  // 多个架构同时发布时，优先取 arm64；通用 APK 作为后备。
  candidates.sort(
    (a, b) => (b.name.contains('arm64') ? 1 : 0).compareTo(
      a.name.contains('arm64') ? 1 : 0,
    ),
  );
  return candidates.firstOrNull;
}

/// 拉取最新 release 的 JSON 文本；失败时说成用户看得懂的一句话。
Future<String> fetchLatestRelease(Uri url) async {
  final client = HttpClient()..connectionTimeout = updateCheckTimeout;
  try {
    final request = await client.getUrl(url).timeout(updateCheckTimeout);
    request.headers.set(HttpHeaders.userAgentHeader, 'YCode-Android');
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    final response = await request.close().timeout(updateCheckTimeout);
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(updateCheckTimeout);
    // 仓库还没有发布过版本（或还不公开）时 GitHub 答 404。
    if (response.statusCode == HttpStatus.notFound) {
      throw UserFacingError(
        AppState.phrase(
          'GitHub 上还没有发布的版本。',
          'No release has been published on GitHub yet.',
        ),
      );
    }
    if (response.statusCode != HttpStatus.ok) {
      throw UserFacingError(
        AppState.phrase(
          'GitHub 暂时无法提供更新信息，请稍后重试。',
          'GitHub cannot provide update information right now. Try again later.',
        ),
      );
    }
    return body;
  } finally {
    // 网络上的失败交给 [checkForUpdate] 统一说成一句话。
    client.close(force: true);
  }
}

/// 取最新版本，和 [currentVersion] 比一比。网络用 [fetcher] 注入，测试不联网。
Future<UpdateCheck> checkForUpdate({
  required String currentVersion,
  ReleaseFetcher fetcher = fetchLatestRelease,
}) async {
  final String body;
  try {
    body = await fetcher(Uri.parse(updateReleaseApi));
  } on UserFacingError {
    rethrow;
  } on Object {
    throw UserFacingError(
      AppState.phrase(
        '检查更新失败，请检查网络后重试。',
        'Could not check for updates. Check the network and retry.',
      ),
    );
  }
  final ReleaseInfo latest;
  try {
    latest = parseRelease(body);
  } on Object {
    throw UserFacingError(
      AppState.phrase(
        '更新信息无法识别，请稍后重试。',
        'The update information could not be read. Try again later.',
      ),
    );
  }
  final order = compareVersions(currentVersion, latest.version);
  return UpdateCheck(
    latest: latest,
    comparable: order != null,
    newer: order != null && order < 0,
  );
}

/// 打开应用时的自动检查：冷启动和每次回到前台都检查一次。[reuse] 内复用上次
/// 的结果，不重复请求 GitHub（匿名接口每个出口 IP 每小时只有 60 次）；同时触发的
/// 检查共用一次请求。只有发现可下载的新版本才返回结果，失败不提示也不记下，下次
/// 打开再试。
class AutoUpdateChecker {
  AutoUpdateChecker({
    required this.currentVersion,
    this.fetcher = fetchLatestRelease,
    DateTime Function()? now,
  }) : _now = now ?? clock.now;

  static const reuse = Duration(minutes: 30);

  final String currentVersion;
  final ReleaseFetcher fetcher;
  final DateTime Function() _now;
  DateTime? _checkedAt;
  UpdateCheck? _found;
  Future<UpdateCheck?>? _running;

  Future<UpdateCheck?> check() =>
      _running ??= _check().whenComplete(() => _running = null);

  Future<UpdateCheck?> _check() async {
    if (normalizeVersion(currentVersion) == null) return null;
    final now = _now();
    final last = _checkedAt;
    if (last != null && now.difference(last) < reuse) return _found;
    final UpdateCheck check;
    try {
      check = await checkForUpdate(
        currentVersion: currentVersion,
        fetcher: fetcher,
      );
    } on Object {
      return null;
    }
    _checkedAt = now;
    return _found = check.newer && check.latest.apk != null ? check : null;
  }
}
