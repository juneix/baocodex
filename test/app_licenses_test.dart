import 'package:baocode_mobile/app_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('开源许可页列出本项目和随应用分发的图标许可全文', () async {
    LicenseRegistry.reset();
    addTearDown(LicenseRegistry.reset);
    registerAppLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    String textOf(String package) => entries
        .where((entry) => entry.packages.contains(package))
        .expand((entry) => entry.paragraphs)
        .map((paragraph) => paragraph.text)
        .join('\n');

    expect(textOf('YCode'), contains('GNU GENERAL PUBLIC LICENSE'));
    expect(textOf('Lucide'), contains('ISC License'));
    // 部分 Lucide 图标衍生自 Feather，MIT 声明也要一起带上。
    expect(textOf('Lucide'), contains('Cole Bemis'));
    expect(textOf('Remix Icon'), contains('Apache License'));
    expect(textOf('theSVG'), contains('thesvg.org'));
    expect(textOf('Material Icon Theme'), contains('Material Extensions'));
  });
}
