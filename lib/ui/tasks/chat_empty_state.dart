import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../files/files_tab.dart' show shortPath;
import '../widgets/lucide_icon.dart';

class ChatEmptyState extends StatefulWidget {
  const ChatEmptyState({
    super.key,
    required this.state,
    required this.online,
    required this.onSuggestion,
    required this.canSuggest,
    this.project,
    this.onSwitchProject,
    this.bot = false,
  });

  final AppState state;
  final bool online, canSuggest, bot;
  final ProjectRef? project;
  final ValueChanged<String> onSuggestion;

  /// Picks another project for the conversation not begun yet.
  final ValueChanged<BuildContext>? onSwitchProject;

  @override
  State<ChatEmptyState> createState() => _ChatEmptyStateState();
}

class _ChatEmptyStateState extends State<ChatEmptyState>
    with WidgetsBindingObserver {
  static const _projectSuggestions = [
    ('讲讲这个项目的整体结构', 'Explain this project’s structure'),
    ('找出最近改动里的一个 bug 并修好', 'Find and fix a bug in the recent changes'),
    ('给今天的改动补上测试', 'Add tests for today’s changes'),
    ('总结当前未提交的改动', 'Summarize the uncommitted changes'),
    ('检查项目的启动方式和依赖', 'Check how to start the project and its dependencies'),
    ('先列出实现计划，不修改文件', 'Make an implementation plan without editing files'),
    ('检查最近的错误日志', 'Review the recent error logs'),
    ('解释这个项目的核心业务流程', 'Explain this project’s core workflow'),
    ('找一个可以改善的交互细节', 'Find an interaction that could be improved'),
  ];
  static const _botSuggestions = [
    ('报告当前系统运行状态', 'Report the current system status'),
    ('帮我整理今天要做的事', 'Help organize today’s tasks'),
    ('你现在可以帮我做什么？', 'What can you help me with right now?'),
    ('总结最近的工作进展', 'Summarize recent work progress'),
    ('帮我检查正在运行的任务', 'Help check the running tasks'),
    ('先给出建议，不执行操作', 'Give suggestions without taking action'),
  ];
  int _batch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _greeting() {
    final state = widget.state;
    if (widget.bot) {
      final name = state.settings.name.trim();
      final who = name.isEmpty ? 'BaoCodeX' : name;
      return state.tr('$who，我帮你…', '$who, I’m here to help…');
    }
    return switch (clock.now().toLocal().hour) {
      >= 5 && < 11 => state.tr('早上好', 'Good morning'),
      >= 11 && < 14 => state.tr('中午好', 'Good afternoon'),
      >= 14 && < 18 => state.tr('下午好', 'Good afternoon'),
      >= 18 && < 23 => state.tr('晚上好', 'Good evening'),
      _ => state.tr('夜深了', 'It’s getting late'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final colors = Theme.of(context).colorScheme;
    final pool = widget.bot ? _botSuggestions : _projectSuggestions;
    final suggestions = [
      for (var index = 0; index < 3; index++)
        state.tr(
          pool[(_batch + index) % pool.length].$1,
          pool[(_batch + index) % pool.length].$2,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.bot) ...[
                    Image.asset(
                      'assets/icons/bot.png',
                      key: const ValueKey('bot-mascot'),
                      height: 156,
                      fit: BoxFit.contain,
                      semanticLabel: state.tr('Bot 吉祥物', 'Bot mascot'),
                      errorBuilder: (_, _, _) => const SizedBox(
                        height: 156,
                        child: Center(child: LucideIcon('bot', size: 72)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text(
                    _greeting(),
                    key: const ValueKey('chat-greeting'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: widget.bot ? TextAlign.left : TextAlign.center,
                    style: (widget.bot
                            ? Theme.of(context).textTheme.headlineLarge
                            : Theme.of(context).textTheme.headlineSmall)
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (!widget.bot) ...[
                    const SizedBox(height: 8),
                    Text(
                      state.tr('今天想做点什么？', 'What would you like to do today?'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                  if (widget.project case final project?) ...[
                    const SizedBox(height: 28),
                    Material(
                      color: colors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(MobileSizes.radius),
                      clipBehavior: Clip.antiAlias,
                      child: Builder(
                        builder: (anchor) => InkWell(
                          key: const ValueKey('new-chat-project'),
                          onTap: widget.onSwitchProject == null
                              ? null
                              : () => widget.onSwitchProject!(anchor),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                LucideIcon(
                                  'folder',
                                  size: 28,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        project.project.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              shortPath(project.project.path),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: MobileTheme.hintStyleOf(
                                                context,
                                              ),
                                            ),
                                          ),
                                          if (project.project.branch
                                              case final branch?
                                              when branch.isNotEmpty) ...[
                                            const SizedBox(width: 10),
                                            LucideIcon(
                                              'git-branch',
                                              size: 14,
                                              color: colors.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              branch,
                                              key: const ValueKey(
                                                'new-chat-branch',
                                              ),
                                              maxLines: 1,
                                              style: MobileTheme.hintStyleOf(
                                                context,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.onSwitchProject != null) ...[
                                  const SizedBox(width: 8),
                                  LucideIcon(
                                    'chevrons-up-down',
                                    size: 20,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  const Spacer(),
                  for (final suggestion in suggestions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: widget.canSuggest
                              ? () => widget.onSuggestion(suggestion)
                              : null,
                          style: TextButton.styleFrom(
                            foregroundColor: colors.onSurface,
                            backgroundColor: colors.surfaceContainerLowest,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(suggestion, softWrap: true),
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('refresh-suggestions'),
                      onPressed: () => setState(
                        () => _batch = (_batch + 3) % pool.length,
                      ),
                      icon: const LucideIcon('refresh-cw', size: 18),
                      label: Text(state.tr('换一换', 'Try others')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
