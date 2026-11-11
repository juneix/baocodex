import '../../state/app_state.dart';

/// 「09:05」：时刻只有这一种写法。
String formatClock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

/// 「11月4日」；不是今年就带上年份。和列表、设备页上的日期一致。
String formatDay(AppState state, DateTime value, {DateTime? now}) {
  now ??= DateTime.now();
  return value.year == now.year
      ? state.tr('${value.month}月${value.day}日', '${value.month}/${value.day}')
      : '${value.year}/${value.month}/${value.day}';
}
