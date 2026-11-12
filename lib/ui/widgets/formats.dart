import 'package:clock/clock.dart';

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

/// 会话列表的相对时间；电脑时钟稍快时也不显示负数。
String relativeTimeText(AppState state, DateTime value, {DateTime? now}) {
  final seconds = (now ?? clock.now()).difference(value).inSeconds;
  if (seconds < 60) return state.tr('刚刚', 'Now');
  final minutes = seconds ~/ 60;
  if (minutes < 60) return state.tr('$minutes分钟', '$minutes min');
  final hours = minutes ~/ 60;
  if (hours < 24) return state.tr('$hours小时', '$hours h');
  final days = hours ~/ 24;
  if (days < 7) return state.tr('$days天', '$days d');
  if (days < 30) {
    final weeks = days ~/ 7;
    return state.tr('$weeks周', '$weeks wk');
  }
  final months = days ~/ 30;
  if (months < 12) return state.tr('$months月', '$months mo');
  final years = days ~/ 365;
  return years < 1
      ? state.tr('$months月', '$months mo')
      : state.tr('$years年', '$years yr');
}
