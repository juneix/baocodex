import 'dart:ui' as ui;

/// Whether the platform locale is Chinese.
bool get localeIsZh =>
    ui.PlatformDispatcher.instance.locale.languageCode == 'zh';

/// The app language as a bare widget sees it: the platform locale. A call
/// site with an `AppState` passes its `state.tr`, which also honors the
/// in-app language setting.
String localeTr(String zh, String en) => localeIsZh ? zh : en;
