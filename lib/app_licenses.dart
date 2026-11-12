// YCode — GPL-3.0-only.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 随应用分发的代码和图标的许可全文，显示在「开源许可」页；
/// 第三方 Dart 包的许可由 Flutter 自动收集，不在这里重复。
const _licenses = [
  (['BaoCodeX', 'YCode upstream', 'BaoCode adapted sources'], 'assets/LICENSE-GPL-3.0.txt'),
  (['Lucide'], 'assets/licenses/lucide.txt'),
  (['Remix Icon'], 'assets/licenses/remix-icon-4.8.0.txt'),
  (['theSVG'], 'assets/licenses/thesvg.txt'),
  (['Material Icon Theme'], 'assets/material_icons/LICENSE'),
];

void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (packages, asset) in _licenses) {
      yield LicenseEntryWithLineBreaks(
        packages,
        await rootBundle.loadString(asset),
      );
    }
  });
}
