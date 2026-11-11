import 'dart:async';

import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../../chat/widgets/agent_step.dart';
import '../../chat/message_view.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/mobile_widgets.dart';
import '../widgets/formats.dart';

String _duration(Duration time, String Function(String zh, String en) tr) =>
    AgentStep.formatDuration(time, strings: AgentStrings(tr('中', 'en') == '中'));

/// Bot 做完一轮后留下的一行“已处理 · 2 分 12 秒”，点开进工作过程页。
class BotWorkFold extends StatelessWidget {
  const BotWorkFold({
    super.key,
    required this.worked,
    required this.tr,
    this.at,
    this.onOpen,
  });

  final Duration worked;
  final String Function(String zh, String en) tr;

  /// 这一轮开始的时刻，写在最前面；没有消息带时间时才给。
  final DateTime? at;

  /// 有过程可看时才给。
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final style = MobileTheme.metaStyleOf(context);
    final time = at?.toLocal();
    return Center(
      child: InkWell(
        key: const ValueKey('bot-work-fold'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${time == null ? '' : '${formatClock(time)} '}'
                '${tr('已处理', 'Worked')} · ${_duration(worked, tr)}',
                style: style,
              ),
              if (onOpen != null)
                Icon(Icons.chevron_right, size: 16, color: style.color),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一轮的工作过程：聊天里不放的步骤都在这里，一页看完。
class BotWorkPage extends StatelessWidget {
  const BotWorkPage({
    super.key,
    required this.state,
    required this.desktopId,
    required this.worked,
    required this.items,
    this.bot,
  });

  final AppState state;
  final String desktopId;
  final Duration worked;
  final List<ChatItem> items;
  final BotRef? bot;

  @override
  Widget build(BuildContext context) {
    final tr = state.tr;
    // 思考不算一步，和做的事分开数。
    final steps = items.where((item) => item is! ThinkingItem).length;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('工作过程', 'Work')),
            Text(
              '${tr('$steps 步', '$steps steps')} · ${_duration(worked, tr)}',
              style: MobileTheme.metaStyleOf(context),
            ),
          ],
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        itemBuilder: (context, index) => MessageView(
          state: state,
          desktopId: desktopId,
          item: items[index],
          bot: bot,
        ),
      ),
    );
  }
}

/// Bot 干活时输入栏上方的一行：转圈、“工作中”和已用时，做完就收起。
class BotWorkingLine extends StatefulWidget {
  const BotWorkingLine({super.key, required this.tr, this.since});

  final String Function(String zh, String en) tr;

  /// 这一轮开始的时刻；不知道时从这一行出现算起。
  final DateTime? since;

  @override
  State<BotWorkingLine> createState() => _BotWorkingLineState();
}

class _BotWorkingLineState extends State<BotWorkingLine> {
  final _shownAt = DateTime.now();
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final since = widget.since ?? _shownAt;
    final elapsed = DateTime.now().difference(since);
    return Padding(
      key: const ValueKey('bot-working'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const ConnectingSpinner(size: 12),
          const SizedBox(width: 6),
          Text(
            '${widget.tr('工作中', 'Working')} · '
            // 电脑和手机的时钟可能差一点，不显示负数。
            '${_duration(elapsed.isNegative ? Duration.zero : elapsed, widget.tr)}',
            style: MobileTheme.metaStyleOf(context),
          ),
        ],
      ),
    );
  }
}
