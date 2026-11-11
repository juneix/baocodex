import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/chat_models.dart';
import '../../chat/message_view.dart';
import '../../link/chat_codec.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/mobile_widgets.dart';
import 'changes_page.dart' show ChangeError;
import 'task_stop_button.dart';
import '../../chat/widgets/agent_step.dart';

/// 子代理详情随会话更新步骤；运行中可确认停止，不提供消息输入。
class SubagentPage extends StatefulWidget {
  const SubagentPage({
    super.key,
    required this.state,
    required this.desktopId,
    this.projectId,
    this.sessionId,
    required this.item,
  });

  final AppState state;
  final String desktopId;
  final String? projectId;
  final String? sessionId;

  /// 打开时的卡片；详情页按标识读取会话中的最新状态。
  final AgentItem item;

  @override
  State<SubagentPage> createState() => _SubagentPageState();
}

class _SubagentPageState extends State<SubagentPage> {
  bool _stopping = false;
  String? _stopError;

  AppState get state => widget.state;
  String get desktopId => widget.desktopId;
  String? get projectId => widget.projectId;
  String? get sessionId => widget.sessionId;
  AgentItem get item => widget.item;

  bool get _canStop =>
      !_stopping &&
      state.isOnline(desktopId) &&
      sessionId != null &&
      _current().id != null &&
      _current().status == CommandStatus.running;

  Future<void> _stop() async {
    if (!_canStop) return;
    final current = _current();
    final confirmed = await confirmTaskStop(
      context,
      state: state,
      description: current.description,
    );
    if (!confirmed || !mounted || !_canStop) return;
    setState(() {
      _stopping = true;
      _stopError = null;
    });
    try {
      await state.request(desktopId, LinkMethods.stopTask, {
        'session': sessionId,
        'agent': current.id,
      });
    } catch (error) {
      if (mounted) {
        setState(() => _stopError = taskStopFailure(widget.state, error));
      }
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  /// The card as the conversation has it now: found again by its id, at any
  /// depth (a subagent's own subagents); as opened when it is no longer held.
  AgentItem _current() {
    final id = item.id;
    final session = sessionId;
    if (id == null || session == null) return item;
    AgentItem? find(Iterable<ChatItem> items) {
      for (final candidate in items) {
        if (candidate is! AgentItem) continue;
        if (candidate.id == id) return candidate;
        if (find(candidate.children) case final nested?) return nested;
      }
      return null;
    }

    final held = state.peekBuffer(desktopId, session)?.items ?? const [];
    return find(held.map(ChatCodec.decode).whereType<ChatItem>()) ?? item;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => _page(context, _current()),
  );

  Widget _page(BuildContext context, AgentItem item) {
    final meta = [
      if (item.agentType != null) (state.tr('类型', 'Type'), item.agentType!),
      if (item.model != null) (state.tr('模型', 'Model'), item.model!),
      if (item.tokens != null) ('token', AgentStep.formatTokens(item.tokens!)),
      if (item.toolUses != null)
        (state.tr('工具调用', 'Tool calls'), '${item.toolUses}'),
      if (item.duration != null)
        (
          state.tr('耗时', 'Duration'),
          AgentStep.formatDuration(
            item.duration!,
            strings: AgentStrings(state.tr('中', 'en') == '中'),
          ),
        ),
      if (item.background)
        (state.tr('运行方式', 'Mode'), state.tr('后台运行', 'Background')),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          item.description.isEmpty
              ? state.tr('子代理', 'Subagent')
              : item.description,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (item.status == CommandStatus.running &&
              item.id != null &&
              sessionId != null)
            StopActionButton(
              tooltip: state.tr('停止', 'Stop'),
              busy: _stopping,
              onPressed: _canStop ? _stop : null,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_stopError != null) ChangeError(_stopError!),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusChip(status: item.status, state: state),
              for (final (label, value) in meta)
                Text(
                  '$label · $value',
                  style: MobileTheme.metaStyleOf(context),
                ),
            ],
          ),
          if (item.activity != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                item.activity!,
                style: MobileTheme.metaStyleOf(context)
                    .copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          if (item.prompt != null)
            _ProseSection(
              state: state,
              title: state.tr('任务', 'Prompt'),
              text: item.prompt!,
            ),
          if (item.children.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 4),
              child: Text(
                state.tr('它的会话', 'Its conversation'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final child in item.children)
              MessageView(
                state: state,
                desktopId: desktopId,
                item: child,
                projectId: projectId,
                sessionId: sessionId,
              ),
          ],
          if (item.result != null)
            _ProseSection(
              state: state,
              title: state.tr('最终报告', 'Final report'),
              text: item.result!,
              copyable: true,
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.state});

  final CommandStatus status;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final colors = MobileTheme.statusColorsOf(context);
    final (label, color) = switch (status) {
      CommandStatus.running => (state.tr('进行中', 'Running'), colors.warning),
      CommandStatus.succeeded => (state.tr('已完成', 'Completed'), colors.success),
      CommandStatus.failed => (
        state.tr('失败', 'Failed'),
        Theme.of(context).colorScheme.error,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: MobileTheme.metaStyleOf(context, color: color)),
    );
  }
}

class _ProseSection extends StatelessWidget {
  const _ProseSection({
    required this.state,
    required this.title,
    required this.text,
    this.copyable = false,
  });

  final AppState state;
  final String title;
  final String text;
  final bool copyable;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            if (copyable)
              IconButton(
                tooltip: state.tr('复制', 'Copy'),
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () => Clipboard.setData(ClipboardData(text: text)),
              ),
          ],
        ),
      ),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
        ),
        child: SelectableText(text, style: MobileTheme.messageStyleOf(context)),
      ),
    ],
  );
}

/// 打开子代理详情页，保留消息流卡片与详情页统一的入口。
void openSubagentPage(
  BuildContext context, {
  required AppState state,
  required String desktopId,
  String? projectId,
  String? sessionId,
  required AgentItem item,
}) {
  openPage<void>(
    context,
    SubagentPage(
      state: state,
      desktopId: desktopId,
      projectId: projectId,
      sessionId: sessionId,
      item: item,
    ),
  );
}
