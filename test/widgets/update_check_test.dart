import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode_mobile/state/apk_download.dart';
import 'package:baocode_mobile/state/update_check.dart';
import 'package:flutter/services.dart';

import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/home_shell.dart';
import 'package:baocode_mobile/ui/settings/settings_page.dart';
import 'package:baocode_mobile/ui/widgets/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget home) =>
    MaterialApp(theme: MobileTheme.build(Brightness.light), home: home);

String releaseJson({
  String tag = 'v0.3.0',
  String notes = '- Fixed a few things\n\n<!-- zh -->\n\n- 修了几个问题\n- 也更稳了',
}) => jsonEncode({
  'tag_name': tag,
  'body': notes,
  'html_url': 'https://github.com/juneix/ycode/releases/tag/$tag',
  'assets': [
    {
      'name': 'BaoCodeX-0.3.0.apk',
      'browser_download_url':
          'https://github.com/juneix/ycode/releases/download/$tag/BaoCodeX-0.3.0.apk',
      'size': 4,
    },
  ],
});

class FailingDownloader extends ApkDownloader {
  FailingDownloader(this.reason);
  final ApkDownloadFailure reason;

  @override
  Future<File> download(
    ReleaseApk apk,
    Directory directory, {
    void Function(int received)? onProgress,
  }) async => throw ApkDownloadException(reason);
}

class CompletedDownloader extends ApkDownloader {
  @override
  Future<File> download(
    ReleaseApk apk,
    Directory directory, {
    void Function(int received)? onProgress,
  }) async {
    onProgress?.call(4);
    return File('${directory.path}/ycode.apk');
  }
}

void main() {
  setUp(() => AppState.debugLanguage = 'zh');
  tearDown(() => AppState.debugLanguage = null);

  testWidgets('有新版本时弹出可滚动说明和下载并安装入口', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    state.settings.language = 'zh';
    var calls = 0;
    final answer = Completer<String>();
    await tester.pumpWidget(
      host(
        Scaffold(
          body: ListView(
            children: [
              GroupCard(
                children: [
                  UpdateCheckRow(
                    state: state,
                    currentVersion: '0.2.0',
                    fetcher: (_) {
                      calls++;
                      return answer.future;
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('检查更新'));
    await tester.pump();
    // 等结果时行上转圈，再点不重复发请求。
    expect(find.byType(ConnectingSpinner), findsOneWidget);
    await tester.tap(find.text('检查更新'), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);

    answer.complete(releaseJson());
    await tester.pumpAndSettle();
    expect(find.byType(ConnectingSpinner), findsNothing);

    expect(find.byType(UpdateDialog), findsOneWidget);
    expect(find.text('发现新版本 0.3.0'), findsOneWidget);
    expect(find.text('更新说明'), findsOneWidget);
    expect(find.textContaining('修了几个问题'), findsOneWidget);
    expect(find.textContaining('Fixed', findRichText: true), findsNothing);
    expect(find.textContaining('<!--', findRichText: true), findsNothing);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('下载并安装'), findsOneWidget);

    await tester.tap(find.text('以后再说'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('只有说明没有 APK 时不能下载', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    state.settings.language = 'zh';
    addTearDown(state.dispose);
    await tester.pumpWidget(
      host(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => UpdateDialog(
                  state: state,
                  release: const ReleaseInfo(
                    version: '0.3.0',
                    notes: '',
                    url: 'https://github.com/juneix/ycode/releases/tag/v0.3.0',
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('此版本尚未提供可用的 Android 安装包。'), findsOneWidget);
    expect(find.text('下载并安装'), findsNothing);
  });

  testWidgets('下载后安装需要授权时可返回继续安装', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    state.settings.language = 'zh';
    final directory = Directory('/test/ycode');
    const channel = MethodChannel('local.baocode.mobile/platform');
    var installs = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'updateDirectory') return directory.path;
          if (call.method == 'installUpdate') {
            expect(call.arguments['version'], '0.3.0');
            expect(call.arguments['size'], 4);
            expect(call.arguments['path'], '/test/ycode/ycode.apk');
            return ++installs > 1;
          }
          throw MissingPluginException();
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(
      host(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => UpdateDialog(
                  state: state,
                  release: parseRelease(releaseJson()),
                  downloader: CompletedDownloader(),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载并安装'));
    await tester.pumpAndSettle();
    expect(find.text('继续安装'), findsOneWidget);
    expect(find.textContaining('允许 YCode 安装应用'), findsOneWidget);
    await tester.tap(find.text('继续安装'));
    await tester.pumpAndSettle();
    expect(installs, 2);
    expect(find.text('已打开系统安装器，请按系统提示完成安装。'), findsOneWidget);
    expect(find.text('继续安装'), findsNothing);
  });

  testWidgets('下载失败按原因提示：网络问题不提存储空间', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    state.settings.language = 'zh';
    const channel = MethodChannel('local.baocode.mobile/platform');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => '/test/ycode');
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    for (final (reason, shown, hidden) in [
      (ApkDownloadFailure.network, '下载失败，请检查网络后重试。', '存储空间'),
      (ApkDownloadFailure.incomplete, '下载的文件不完整，请重新下载。', '存储空间'),
      (ApkDownloadFailure.storage, '无法保存安装包，请检查手机存储空间后重试。', '网络'),
    ]) {
      await tester.pumpWidget(
        host(
          Scaffold(
            body: UpdateDialog(
              key: ValueKey(reason),
              state: state,
              release: parseRelease(releaseJson()),
              downloader: FailingDownloader(reason),
            ),
          ),
        ),
      );
      await tester.tap(find.text('下载并安装'));
      await tester.pumpAndSettle();
      expect(find.text(shown), findsOneWidget, reason: '$reason');
      expect(find.textContaining(hidden), findsNothing, reason: '$reason');
      expect(find.text('下载并安装'), findsOneWidget, reason: '失败后可以重试');
    }
  });

  /// 切到别的应用再回来：按系统真实的生命周期顺序走一遍。
  void toBackgroundAndBack(WidgetTester tester) {
    for (final lifecycle in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(lifecycle);
    }
  }

  AutoUpdateChecker newerChecker(void Function() onFetch) => AutoUpdateChecker(
    currentVersion: '0.2.0',
    fetcher: (_) async {
      onFetch();
      return releaseJson();
    },
  );

  testWidgets('打开应用发现可下载的新版本就弹出更新窗口', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    state.settings.language = 'zh';
    var fetches = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          state: state,
          updateChecker: newerChecker(() => fetches++),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fetches, 1);
    expect(find.text('发现新版本 0.3.0'), findsOneWidget);
    expect(find.text('下载并安装'), findsOneWidget);
  });

  testWidgets('点以后再说后，从后台回到应用会再次提示', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    state.settings.language = 'zh';
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(state: state, updateChecker: newerChecker(() {})),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('以后再说'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);

    toBackgroundAndBack(tester);
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 0.3.0'), findsOneWidget);
  });

  testWidgets('更新窗口开着时回到应用不重复弹出', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    state.settings.language = 'zh';
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(state: state, updateChecker: newerChecker(() {})),
      ),
    );
    await tester.pumpAndSettle();
    // 比如去系统设置里允许安装未知应用，再回来。
    toBackgroundAndBack(tester);
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsOneWidget);
  });

  testWidgets('没有新版本时不打扰，演示模式不检查', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          state: state,
          updateChecker: AutoUpdateChecker(
            currentVersion: '0.3.0',
            fetcher: (_) async => releaseJson(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);

    final demo = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(demo.dispose);
    var fetched = false;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          state: demo,
          updateChecker: newerChecker(() => fetched = true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fetched, isFalse);
  });

  testWidgets('已是最新时只说一句，不弹说明', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    state.settings.language = 'zh';
    await tester.pumpWidget(
      host(
        Scaffold(
          body: UpdateCheckRow(
            state: state,
            currentVersion: '0.3.0',
            fetcher: (_) async => releaseJson(),
          ),
        ),
      ),
    );
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
    expect(find.text('已是最新版本（0.3.0）'), findsOneWidget);
  });

  testWidgets('dev 构建不比较，只说最新版本是多少', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    state.settings.language = 'zh';
    await tester.pumpWidget(
      host(
        Scaffold(
          body: UpdateCheckRow(
            state: state,
            currentVersion: 'dev',
            fetcher: (_) async => releaseJson(),
          ),
        ),
      ),
    );
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
    expect(find.text('这个构建没有版本号'), findsOneWidget);
    expect(find.textContaining('0.3.0'), findsWidgets);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('这个构建没有版本号'), findsNothing);
  });

  testWidgets('检查失败走一句人话，不露异常原文', (tester) async {
    final state = AppState(store: MemoryLinkStore());
    addTearDown(state.dispose);
    state.settings.language = 'zh';
    await tester.pumpWidget(
      host(
        Scaffold(
          body: UpdateCheckRow(
            state: state,
            currentVersion: '0.2.0',
            fetcher: (_) async => throw Exception('socket closed'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.text('检查更新失败，请检查网络后重试。'), findsOneWidget);
    expect(find.textContaining('socket closed'), findsNothing);
  });
}
