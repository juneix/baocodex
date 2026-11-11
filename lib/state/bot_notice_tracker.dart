import 'package:bao_link/bao_link.dart';

/// 仅在内存中记录每个（电脑，Bot）已见过的最新通知 ID，使每条通知在一个
/// 进程内最多提醒一次。
class BotNoticeTracker {
  final _marks = <(String, String), int>{};

  /// [bot] 中此前未见过的通知，按 ID 从小到大排列。某个（电脑，Bot）的首次
  /// 调用只记录已有通知，不返回。
  List<LinkBotNotice> accept(String desktopId, LinkBot bot) {
    final key = (desktopId, bot.id);
    final valid = {
      for (final notice in bot.notices)
        if (notice.id > 0) notice.id: notice,
    };
    final newest = valid.keys.fold(0, (a, b) => a > b ? a : b);
    final mark = _marks[key];
    if (mark == null) {
      _marks[key] = newest;
      return const [];
    }
    final fresh = [
      for (final entry in valid.entries)
        if (entry.key > mark) entry.value,
    ]..sort((a, b) => a.id.compareTo(b.id));
    if (newest > mark) _marks[key] = newest;
    return fresh;
  }

  void forgetDesktop(String desktopId) =>
      _marks.removeWhere((key, _) => key.$1 == desktopId);
}
