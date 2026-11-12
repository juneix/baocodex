// YCode — GPL-3.0-only.
import 'dart:io';

import 'package:baocode_mobile/ui/settings/changelog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_page_harness.dart';

class _Bundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(File(key).readAsBytesSync());
}

void main() {
  testWidgets('中英两份更新日志随包分发，都写着 pubspec 的这一版，按界面语言显示', (tester) async {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
    for (final (state, file, title) in [
      (ChineseChatPageState(), changelogAssets.zh, '更新日志'),
      (ChatPageState(), changelogAssets.en, 'Changelog'),
    ]) {
      addTearDown(state.dispose);
      expect(pubspec, contains('    - $file\n'));
      expect(
        File(file).readAsStringSync(),
        contains('\n## $version\n'),
        reason: '发版前在 $file 写上 $version',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ChangelogPage(
            key: ValueKey(file),
            state: state,
            bundle: _Bundle(),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.textContaining(version), findsWidgets);
      expect(find.text(title), findsOneWidget, reason: '文件自己的一级标题不重复');
    }
  });
}
