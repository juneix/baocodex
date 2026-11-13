// 生成随 Release 上传的 latest.json：dart run tool/release_manifest.dart
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _defaultRepository = 'juneix/baocodex';
const _outputs = 'build/app/outputs/flutter-apk';

void main(List<String> arguments) {
  String? argumentRepository;
  for (final argument in arguments) {
    const prefix = '--repository=';
    if (!argument.startsWith(prefix) || argumentRepository != null) {
      _fail('用法：dart run tool/release_manifest.dart [--repository=<owner/repo>]');
    }
    argumentRepository = argument.substring(prefix.length);
  }
  final repository = argumentRepository ??
      Platform.environment['YCODE_REPOSITORY'] ??
      _defaultRepository;
  if (!RegExp(
    r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?/'
    r'[A-Za-z0-9](?:[A-Za-z0-9_.-]{0,98}[A-Za-z0-9_])?$',
  ).hasMatch(repository)) {
    _fail('发布仓库必须是有效的 owner/repo：$repository');
  }
  final releases = 'https://github.com/$repository/releases';

  final version = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync());
  if (version == null) _fail('pubspec.yaml 的 version 必须是三段数字，如 1.0.3');
  final name = version[1]!;
  final tag = 'v$name';
  final apkName = 'BaoCodeX-$name.apk';
  final apk = File('$_outputs/$apkName');
  if (!apk.existsSync()) {
    _fail('找不到 ${apk.path}，先运行 tool/build_android.sh --no-install');
  }
  final bytes = apk.readAsBytesSync();
  final manifest = {
    'tag_name': tag,
    'html_url': '$releases/tag/$tag',
    // 应用按界面语言只显示一半；分隔行同 update_check.dart 的 releaseNotesZhMarker。
    'body': [
      _section('CHANGELOG.md', name),
      _section('CHANGELOG_CN.md', name),
    ].join('\n\n<!-- zh -->\n\n'),
    'assets': [
      {
        'name': apkName,
        'browser_download_url': '$releases/download/$tag/$apkName',
        'size': bytes.length,
        'digest': 'sha256:${sha256.convert(bytes)}',
      },
    ],
  };
  final out = File('$_outputs/latest.json')
    ..writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
  stdout.writeln(out.path);
}

String _section(String path, String version) {
  final lines = File(path).readAsLinesSync();
  final start = lines.indexOf('## $version');
  if (start < 0) _fail('$path 里没有「## $version」这一节');
  return lines
      .skip(start + 1)
      .takeWhile((line) => !line.startsWith('## '))
      .join('\n')
      .trim();
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
