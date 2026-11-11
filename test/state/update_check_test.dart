import 'dart:async';
import 'dart:convert';

import 'package:baocode_mobile/models/user_facing_error.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/state/update_check.dart';
import 'package:flutter_test/flutter_test.dart';

String releaseJson({
  String tag = 'v0.3.0',
  String notes = '更稳了',
  String url = 'https://github.com/shuishani/ycode/releases/tag/v0.3.0',
}) => jsonEncode({'tag_name': tag, 'body': notes, 'html_url': url});

void main() {
  setUp(() => AppState.debugLanguage = 'zh');
  tearDown(() => AppState.debugLanguage = null);

  group('版本号比较', () {
    test('带不带 v 都按三段数字比', () {
      expect(compareVersions('0.2.0', 'v0.3.0'), lessThan(0));
      expect(compareVersions('v0.2.0', 'v0.2.0'), 0);
      expect(compareVersions('1.0.0', 'v0.9.9'), greaterThan(0));
      expect(compareVersions('0.10.0', '0.9.0'), greaterThan(0));
      expect(compareVersions('v0.2.1', '0.2.0'), greaterThan(0));
    });

    test('不是三段数字的一律没法比', () {
      for (final text in [
        '',
        'dev',
        'v0.2',
        '0.2.0.1',
        'v0.2.0-beta',
        'x.y.z',
      ]) {
        expect(normalizeVersion(text), isNull, reason: text);
        expect(compareVersions(text, '0.2.0'), isNull, reason: text);
        expect(compareVersions('0.2.0', text), isNull, reason: text);
      }
    });

    test('前导零按数字算', () {
      expect(normalizeVersion('v00.02.000'), '0.2.0');
      expect(compareVersions('0.02.0', '0.2.0'), 0);
    });
  });

  test('个人仓库的版本页和安装包必须使用同一个指定更新源', () {
    final body = jsonEncode({
      'tag_name': 'v0.1.2',
      'html_url': 'https://github.com/personal/ycode/releases/tag/v0.1.2',
      'assets': [
        {
          'name': 'ycode-0.1.2-3.apk',
          'browser_download_url':
              'https://github.com/personal/ycode/releases/download/v0.1.2/ycode-0.1.2-3.apk',
          'size': 1234,
        },
      ],
    });
    final release = parseRelease(body, repository: 'personal/ycode');
    expect(release.version, '0.1.2');
    expect(release.apk?.name, 'ycode-0.1.2-3.apk');
    expect(() => parseRelease(body), throwsFormatException);
    expect(() => parseRelease(body, repository: '../personal/ycode'),
        throwsFormatException);
    final foreignAsset = body.replaceAll(
      'personal/ycode/releases/download/',
      'another/ycode/releases/download/',
    );
    expect(parseRelease(foreignAsset, repository: 'personal/ycode').apk, isNull);
  });

  group('解析 release', () {
    test('取出标签、说明和页面，标签去掉 v', () {
      final release = parseRelease(
        '{"tag_name":"v0.3.1","body":"修了几个问题","html_url":"https://github.com/shuishani/ycode/releases/tag/v0.3.1"}',
      );
      expect(release.version, '0.3.1');
      expect(release.notes, '修了几个问题');
      expect(release.url, contains('/releases/tag/v0.3.1'));
      expect(release.notesZh, isNull);

      final both = parseRelease(
        releaseJson(notes: '- Faster\n\n<!-- zh -->\n\n- 更快了\n'),
      );
      expect(both.notes, '- Faster');
      expect(both.notesZh, '- 更快了');
    });

    test('没有说明正文时为空', () {
      expect(
        parseRelease(
          '{"tag_name":"v0.3.0","html_url":"https://github.com/shuishani/ycode/releases/tag/v0.3.0"}',
        ).notes,
        '',
      );
    });

    test('格式不对就抛 FormatException', () {
      for (final body in [
        'not json',
        '[]',
        '{}',
        '{"tag_name":"dev","html_url":"https://example.com/r"}',
        '{"tag_name":"v0.2.0"}',
        '{"tag_name":"v0.2.0","html_url":"ftp://example.com/r"}',
      ]) {
        expect(
          () => parseRelease(body),
          throwsA(isA<FormatException>()),
          reason: body,
        );
      }
    });
  });

  group('更新安装包', () {
    test('拒绝不属于本项目的版本页', () {
      expect(
        () => parseRelease(releaseJson(url: 'https://example.com/release')),
        throwsFormatException,
      );
    });

    test('选择本项目的 arm64 APK 并读取大小和摘要', () {
      final release = parseRelease(
        jsonEncode({
          'tag_name': 'v0.3.0',
          'html_url': 'https://github.com/shuishani/ycode/releases/tag/v0.3.0',
          'assets': [
            {
              'name': 'ycode-0.3.0.apk',
              'browser_download_url': 'https://github.com/shuishani/ycode/releases/download/v0.3.0/ycode-0.3.0.apk',
              'size': 1234,
              'digest': 'sha256:${'a' * 64}',
            },
          ],
        }),
      );
      expect(release.apk?.name, 'ycode-0.3.0.apk');
      expect(release.apk?.size, 1234);
      expect(release.apk?.sha256, 'a' * 64);
    });

    test('外部地址、错误架构和空安装包不能作为更新', () {
      for (final asset in [
        {
          'name': 'ycode.apk',
          'browser_download_url': 'https://example.com/a.apk',
          'size': 12,
        },
        {
          'name': 'ycode-x86_64.apk',
          'browser_download_url': 'https://github.com/shuishani/ycode/releases/download/v0.3.0/a.apk',
          'size': 12,
        },
        {
          'name': 'ycode.apk',
          'browser_download_url': 'https://github.com/shuishani/ycode/releases/download/v0.3.0/a.apk',
          'size': 0,
        },
      ]) {
        final release = parseRelease(
          jsonEncode({
            'tag_name': 'v0.3.0',
            'html_url':
                'https://github.com/shuishani/ycode/releases/tag/v0.3.0',
            'assets': [asset],
          }),
        );
        expect(release.apk, isNull);
      }
    });
  });

  group('打开应用时自动检查', () {
    String withApk() => jsonEncode({
      'tag_name': 'v0.3.0',
      'html_url': 'https://github.com/shuishani/ycode/releases/tag/v0.3.0',
      'assets': [
        {
          'name': 'ycode-0.3.0-40.apk',
          'browser_download_url': 'https://github.com/shuishani/ycode/releases/download/v0.3.0/ycode-0.3.0-40.apk',
          'size': 1234,
        },
      ],
    });

    test('第一次打开就检查，发现可下载的新版本时返回', () async {
      var fetches = 0;
      final checker = AutoUpdateChecker(
        currentVersion: '0.2.0',
        fetcher: (_) async {
          fetches++;
          return withApk();
        },
      );
      expect((await checker.check())?.latest.version, '0.3.0');
      expect(fetches, 1);
    });

    test('30 分钟内再次打开不重复请求，但新版本照样返回', () async {
      var now = DateTime.utc(2026, 11, 11, 12);
      var fetches = 0;
      final checker = AutoUpdateChecker(
        currentVersion: '0.2.0',
        now: () => now,
        fetcher: (_) async {
          fetches++;
          return withApk();
        },
      );
      await checker.check();
      now = now.add(const Duration(minutes: 29));
      expect((await checker.check())?.latest.version, '0.3.0');
      expect(fetches, 1);
      now = now.add(const Duration(minutes: 1));
      await checker.check();
      expect(fetches, 2);
    });

    test('同时触发的检查只请求一次', () async {
      var fetches = 0;
      final answer = Completer<String>();
      final checker = AutoUpdateChecker(
        currentVersion: '0.2.0',
        fetcher: (_) {
          fetches++;
          return answer.future;
        },
      );
      final first = checker.check();
      final second = checker.check();
      answer.complete(withApk());
      expect((await first)?.latest.version, '0.3.0');
      expect((await second)?.latest.version, '0.3.0');
      expect(fetches, 1);
    });

    test('检查失败不打扰，下次打开立刻重试', () async {
      var fail = true;
      var fetches = 0;
      final checker = AutoUpdateChecker(
        currentVersion: '0.2.0',
        fetcher: (_) async {
          fetches++;
          if (fail) throw Exception('rate limited');
          return withApk();
        },
      );
      expect(await checker.check(), isNull);
      fail = false;
      expect((await checker.check())?.latest.version, '0.3.0');
      // 失败那次先问 latest.json 再问接口。
      expect(fetches, 3);
    });

    test('dev 构建不检查', () async {
      var fetched = false;
      final checker = AutoUpdateChecker(
        currentVersion: 'dev',
        fetcher: (_) async {
          fetched = true;
          return withApk();
        },
      );
      expect(await checker.check(), isNull);
      expect(fetched, isFalse);
    });

    test('新版本没有 APK 或不比当前新时不提示', () async {
      for (final (version, body) in [
        ('0.2.0', releaseJson()),
        ('0.3.0', withApk()),
      ]) {
        final checker = AutoUpdateChecker(
          currentVersion: version,
          fetcher: (_) async => body,
        );
        expect(await checker.check(), isNull, reason: version);
      }
    });
  });

  group('检查更新', () {
    test('更新的版本：可比、是新的', () async {
      final check = await checkForUpdate(
        currentVersion: '0.2.0',
        fetcher: (_) async => releaseJson(),
      );
      expect(check.comparable, isTrue);
      expect(check.newer, isTrue);
      expect(check.latest.version, '0.3.0');
    });

    test('同一版本：可比、不是新的', () async {
      final check = await checkForUpdate(
        currentVersion: 'v0.3.0',
        fetcher: (_) async => releaseJson(),
      );
      expect(check.comparable, isTrue);
      expect(check.newer, isFalse);
    });

    test('线上更旧：可比、不是新的', () async {
      final check = await checkForUpdate(
        currentVersion: '0.4.0',
        fetcher: (_) async => releaseJson(),
      );
      expect(check.comparable, isTrue);
      expect(check.newer, isFalse);
    });

    test('dev 构建：不可比，但仍报出最新版本', () async {
      final check = await checkForUpdate(
        currentVersion: 'dev',
        fetcher: (_) async => releaseJson(),
      );
      expect(check.comparable, isFalse);
      expect(check.newer, isFalse);
      expect(check.latest.version, '0.3.0');
    });

    test('坏数据说人话，不露异常原文', () async {
      await expectLater(
        checkForUpdate(currentVersion: '0.2.0', fetcher: (_) async => '{'),
        throwsA(
          isA<UserFacingError>().having(
            (error) => error.message,
            'message',
            '更新信息无法识别，请稍后重试。',
          ),
        ),
      );
    });

    test('拉取失败说人话，不露异常原文', () async {
      await expectLater(
        checkForUpdate(
          currentVersion: '0.2.0',
          fetcher: (_) async => throw Exception('socket closed'),
        ),
        throwsA(
          isA<UserFacingError>().having(
            (error) => error.message,
            'message',
            '检查更新失败，请检查网络后重试。',
          ),
        ),
      );
    });

    test('先读 Release 附带的 latest.json，读不到或读不懂再问接口', () async {
      for (final (manifest, version) in [
        (releaseJson(tag: 'v0.4.0'), '0.4.0'),
        (null, '0.3.0'),
        ('{', '0.3.0'),
      ]) {
        final asked = <String>[];
        final check = await checkForUpdate(
          currentVersion: '0.2.0',
          fetcher: (url) async {
            asked.add('$url');
            if ('$url' == updateReleaseApi) return releaseJson();
            return manifest ?? (throw Exception('404'));
          },
        );
        expect(check.latest.version, version, reason: manifest);
        expect(asked, [
          updateManifestUrl,
          if (version == '0.3.0') updateReleaseApi,
        ], reason: manifest);
      }
      expect(
        updateManifestUrl,
        'https://github.com/shuishani/ycode/releases/latest/download/latest.json',
      );
      expect(
        updateReleaseApi,
        contains('/repos/shuishani/ycode/releases/latest'),
      );
    });
  });
}
