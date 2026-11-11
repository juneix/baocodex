import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../state/app_state.dart';
import '../widgets/lucide_icon.dart';
import '../files/files_tab.dart' show shortPath;
import '../../theme/app_theme.dart';

class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({
    super.key,
    required this.state,
    required this.online,
    required this.onSuggestion,
    required this.canSuggest,
    this.project,
    this.onSwitchProject,
  });

  final AppState state;
  final bool online, canSuggest;
  final ProjectRef? project;
  final ValueChanged<String> onSuggestion;

  /// Picks another project for the conversation not begun yet; null when
  /// it cannot change.
  final ValueChanged<BuildContext>? onSwitchProject;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final suggestions = [
      state.tr('讲讲这个项目的整体结构', 'Explain this project’s structure'),
      state.tr(
        '找出最近改动里的一个 bug 并修好',
        'Find and fix a bug in the recent changes',
      ),
      state.tr('给今天的改动补上测试', 'Add tests for today’s changes'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: SvgPicture.asset(
                        'assets/icons/ycode.svg',
                        width: 56,
                        height: 56,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      state.tr('要做点什么？', 'What would you like to do?'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          online && !state.demo
                              ? Icons.lock_outline
                              : Icons.chat_bubble_outline,
                          size: 16,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            state.demo
                                ? state.tr('演示对话', 'Demo conversation')
                                : online
                                ? state.tr('端到端加密', 'End-to-end encrypted')
                                : state.tr(
                                    '连接电脑后开始对话',
                                    'Connect a desktop to begin',
                                  ),
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                    if (project case final project?) ...[
                      const SizedBox(height: 28),
                      Material(
                        color: colors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(MobileSizes.radius),
                        clipBehavior: Clip.antiAlias,
                        child: Builder(
                          builder: (anchor) => InkWell(
                            key: const ValueKey('new-chat-project'),
                            onTap: onSwitchProject == null
                                ? null
                                : () => onSwitchProject!(anchor),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  // A folder, as the desktop's own picker shows
                                  // a project; its own colours are for lists.
                                  Container(
                                    width: 44,
                                    height: 44,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: colors.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: LucideIcon(
                                      'folder',
                                      size: 22,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                        // One line: the folder, cut short when
                                        // it must be, then the branch in full.
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
                                  if (onSwitchProject != null) ...[
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
                    const SizedBox(height: 32),
                    const Spacer(),
                    for (final suggestion in suggestions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: canSuggest
                                ? () => onSuggestion(suggestion)
                                : null,
                            // Secondary text, not a button's bolder label.
                            style: TextButton.styleFrom(
                              foregroundColor: colors.onSurface,
                              backgroundColor: colors.surfaceContainerLowest,
                              textStyle: Theme.of(context).textTheme.bodySmall,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: LucideIcon(
                              'sparkles',
                              size: 16,
                              color: colors.primary,
                            ),
                            label: Text(suggestion, softWrap: true),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
