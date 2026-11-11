import 'dart:io';

import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/widgets/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('列表行：模型、标签、时间靠右排满，标题拿剩下的', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: const Scaffold(
          body: ListRow(
            leading: SizedBox(),
            title: '对话图片复制失败逻辑分析和一个很长的标题',
            aside: Text('Opus 5.5'),
            note: '首页',
            time: '20:51',
          ),
        ),
      ),
    );
    final title = tester.getRect(find.textContaining('对话图片'));
    final model = tester.getRect(find.text('Opus 5.5'));
    final tag = tester.getRect(find.text('首页'));
    final time = tester.getRect(find.text('20:51'));
    expect(title.right, lessThanOrEqualTo(model.left));
    expect(model.right, lessThan(tag.left));
    expect(tag.right, lessThan(time.left));
    // 右边那组完整显示，没被截断。
    expect(tester.getSize(find.text('Opus 5.5')).width, greaterThan(40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('长设置值在窄屏大字号下换到标签下方并保持完整', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const value = 'ssh://development-computer/home/user/projects/mobile';
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: SettingsRow('项目地址', value: value, onTap: () {}),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.text(value)).dy,
      greaterThan(tester.getBottomLeft(find.text('项目地址')).dy),
    );
    expect(tester.widget<Text>(find.text(value)).maxLines, isNull);
    expect(
      tester.widget<Text>(find.text('项目地址')).style?.fontSize,
      tester.widget<Text>(find.text(value)).style?.fontSize,
    );
    expect(
      tester.getSize(find.byType(SettingsRow)).height,
      greaterThanOrEqualTo(48),
    );
  });

  test('页面不写死字号数字，只用 MobileType 档位', () {
    final literal = RegExp(r'fontSize:\s*\d');
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            !file.path.endsWith('app_theme.dart'))
          for (final (index, line) in file.readAsLinesSync().indexed)
            if (literal.hasMatch(line)) '${file.path}:${index + 1}',
    ];
    expect(offenders, isEmpty);
  });
}
