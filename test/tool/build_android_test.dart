import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('构建号取显式版本且无论成败保留插件注册文件', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ycode-build-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    Future<void> write(
      String path,
      String content, {
      bool executable = false,
    }) async {
      final file = File('${directory.path}/$path');
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      if (executable) await Process.run('chmod', ['700', file.path]);
    }

    await write(
      'tool/build_android.sh',
      await File('tool/build_android.sh').readAsString(),
    );
    await write('pubspec.yaml', 'version: 0.3.0+35\n');
    const registrant =
        'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java';
    const original =
        '保留本地已有内容\n    try {\n      integration_test;\n    }\n其他插件\n';
    await write(registrant, original);
    await write(
      'signing.properties',
      'storeFile=release.jks\nstorePassword=test\nkeyAlias=test\nkeyPassword=test\n',
    );
    await write('release.jks', 'test-only');
    await write(
      'bin/flutter',
      '#!/bin/sh\nprintf "%s\\n" "\$@" > flutter-args\nmkdir -p build/app/outputs/flutter-apk\ntouch build/app/outputs/flutter-apk/app-release.apk\n',
      executable: true,
    );
    await write(
      'tools/zipalign',
      '#!/bin/sh\nfor arg do last="\$arg"; done\ntouch "\$last"\n',
      executable: true,
    );
    await write(
      'tools/apksigner',
      '#!/bin/sh\nwhile [ "\$#" -gt 0 ]; do\n if [ "\$1" = --out ]; then shift; touch "\$1"; fi\n shift\ndone\n',
      executable: true,
    );
    final environment = {
      'PATH': '${directory.path}/bin:${Platform.environment['PATH']}',
      'BUILD_TOOLS': '${directory.path}/tools',
      'YCODE_SIGNING': '${directory.path}/signing.properties',
    };
    final result = await Process.run(
      'bash',
      ['tool/build_android.sh', '--no-install'],
      workingDirectory: directory.path,
      environment: environment,
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final arguments = await File('${directory.path}/flutter-args')
        .readAsLines();
    expect(arguments, contains('--build-number=35'));
    expect(arguments, contains('--dart-define=APP_VERSION=0.3.0'));
    expect(
      await File('${directory.path}/$registrant').readAsString(),
      original,
    );

    await write('bin/flutter', '#!/bin/sh\nexit 7\n', executable: true);
    final failed = await Process.run(
      'bash',
      ['tool/build_android.sh', '--no-install'],
      workingDirectory: directory.path,
      environment: environment,
    );
    expect(failed.exitCode, 7);
    expect(
      await File('${directory.path}/$registrant').readAsString(),
      original,
    );

    // 上次打包被强制中断时，文件里已经没有 integration_test；不能把它当原件。
    const stripped = '保留本地已有内容\n其他插件\n';
    await write(registrant, stripped);
    await File('${directory.path}/flutter-args').delete();
    await write(
      'bin/flutter',
      '#!/bin/sh\nprintf "%s\\n" "\$@" > flutter-args\n',
      executable: true,
    );
    final interrupted = await Process.run(
      'bash',
      ['tool/build_android.sh', '--no-install'],
      workingDirectory: directory.path,
      environment: environment,
    );
    expect(interrupted.exitCode, isNot(0));
    expect(interrupted.stderr, contains('GeneratedPluginRegistrant.java'));
    expect(File('${directory.path}/flutter-args').existsSync(), isFalse);
    expect(
      await File('${directory.path}/$registrant').readAsString(),
      stripped,
    );
  });
}
