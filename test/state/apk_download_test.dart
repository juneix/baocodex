import 'dart:async';
import 'dart:io';

import 'package:baocode_mobile/state/apk_download.dart';
import 'package:baocode_mobile/state/update_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory directory;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    directory = await Directory.systemTemp.createTemp('ycode-update-test-');
  });
  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  Matcher failure(ApkDownloadFailure reason) => throwsA(
    isA<ApkDownloadException>().having((e) => e.reason, 'reason', reason),
  );

  ReleaseApk asset(int size) => ReleaseApk(
    name: 'ycode-0.3.0.apk',
    url: Uri.parse('http://127.0.0.1:${server.port}/ycode.apk'),
    size: size,
  );

  test('流式下载真实响应并报告进度', () async {
    server.listen((request) async {
      request.response.contentLength = 4;
      request.response.add([1, 2, 3, 4]);
      await request.response.close();
    });
    final progress = <int>[];
    final file = await ApkDownloader().download(
      asset(4),
      directory,
      onProgress: progress.add,
    );
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
    expect(progress.last, 4);
  });

  test('重复下载只保留最新一份安装包', () async {
    var round = 0;
    server.listen((request) async {
      round++;
      request.response.add([round, round, round, round]);
      await request.response.close();
    });
    await ApkDownloader().download(asset(4), directory);
    final file = await ApkDownloader().download(asset(4), directory);
    final names = await directory
        .list()
        .map((entry) => entry.uri.pathSegments.last)
        .toList();
    expect(names, ['ycode-update.apk']);
    expect(await file.readAsBytes(), [2, 2, 2, 2]);
  });

  test('失败响应不能当成安装包，算作网络问题', () async {
    server.listen((request) async {
      request.response.statusCode = 404;
      await request.response.close();
    });
    await expectLater(
      ApkDownloader().download(asset(4), directory),
      failure(ApkDownloadFailure.network),
    );
    expect(await directory.list().toList(), isEmpty);
  });

  test('长度不足或超过元数据都不能安装', () async {
    server.listen((request) async {
      request.response.add([1, 2, 3]);
      await request.response.close();
    });
    for (final size in [2, 4]) {
      await expectLater(
        ApkDownloader().download(asset(size), directory),
        failure(ApkDownloadFailure.incomplete),
      );
    }
    expect(await directory.list().toList(), isEmpty);
  });

  test('摘要不匹配不能安装', () async {
    server.listen((request) async {
      request.response.add([1, 2, 3, 4]);
      await request.response.close();
    });
    await expectLater(
      ApkDownloader().download(
        ReleaseApk(
          name: 'ycode.apk',
          url: asset(4).url,
          size: 4,
          sha256: '0' * 64,
        ),
        directory,
      ),
      failure(ApkDownloadFailure.incomplete),
    );
    expect(await directory.list().toList(), isEmpty);
  });

  test('连不上服务器算作网络问题', () async {
    final port = server.port;
    await server.close(force: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    await expectLater(
      ApkDownloader().download(
        ReleaseApk(
          name: 'ycode.apk',
          url: Uri.parse('http://127.0.0.1:$port/ycode.apk'),
          size: 4,
        ),
        directory,
      ),
      failure(ApkDownloadFailure.network),
    );
  });

  test('安装包无法写入手机时算作存储问题', () async {
    server.listen((request) async {
      request.response.add([1, 2, 3, 4]);
      await request.response.close();
    });
    final blocker = File('${directory.path}/blocker');
    await blocker.writeAsString('不是目录');
    await expectLater(
      ApkDownloader().download(asset(4), Directory('${blocker.path}/updates')),
      failure(ApkDownloadFailure.storage),
    );
  });

  test('取消中断响应并且不留下半包', () async {
    final started = Completer<void>();
    server.listen((request) async {
      request.response.add([1]);
      await request.response.flush();
      started.complete();
    });
    final downloader = ApkDownloader();
    final future = downloader.download(asset(4), directory);
    final assertion = expectLater(future, throwsA(isA<ApkDownloadCancelled>()));
    await started.future;
    downloader.cancel();
    await assertion;
    expect(await directory.list().toList(), isEmpty);
  });
}
