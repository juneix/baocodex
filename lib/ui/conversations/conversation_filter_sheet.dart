import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/dropdown_panel.dart';
import '../widgets/mobile_widgets.dart';
import 'conversation_filters.dart';

String sourceLabel(AppState state, ConversationSource source) =>
    switch (source) {
      ConversationSource.all => state.tr('全部', 'All'),
      ConversationSource.local => state.tr('本机', 'Local'),
      ConversationSource.remote => 'SSH / WSL',
      ConversationSource.ssh => 'SSH',
      ConversationSource.wsl => 'WSL',
      ConversationSource.unknown => state.tr('未知来源', 'Unknown location'),
    };

String statusLabel(AppState state, ConversationStatus status) =>
    switch (status) {
      ConversationStatus.all => state.tr('全部', 'All'),
      ConversationStatus.active => state.tr(
        '运行中 / 待处理',
        'Running / needs input',
      ),
      ConversationStatus.pinned => state.tr('仅置顶会话', 'Pinned conversations'),
    };

String filterSummary(AppState state, ConversationFilters filters) {
  final project = state.projects
      .where((p) => (p.desktopId, p.project.id) == filters.projectKey)
      .firstOrNull;
  return [
    if (filters.source != ConversationSource.all)
      sourceLabel(state, filters.source),
    if (filters.status != ConversationStatus.all)
      statusLabel(state, filters.status),
    if (filters.projectKey != null)
      project == null
          ? state.tr('项目当前不可用', 'Project unavailable')
          : project.project.name,
    if (filters.sort == ConversationSort.name) state.tr('按名称', 'By name'),
    if (filters.grouping == ConversationGrouping.date)
      state.tr('按更新日期', 'By update date'),
    if (filters.grouping == ConversationGrouping.status)
      state.tr('按状态', 'By status'),
    if (filters.query.trim().isNotEmpty) state.tr('搜索结果', 'Search results'),
  ].join(' · ');
}

/// 贴着按钮弹出：点选即时生效，关闭不撤销筛选，也不改动搜索词。
Future<void> showConversationFilters(
  BuildContext anchor,
  AppState state,
  ConversationFilters current,
  ValueChanged<ConversationFilters> onChanged, {
  bool projectSelection = true,
}) {
  var draft = current;
  return showDropdownPanel<void>(
    anchor,
    align: DropdownAlign.start,
    width: 340,
    builder: (context) => StatefulBuilder(
      builder: (context, update) {
        void pick(ConversationFilters next) {
          update(() => draft = next);
          onChanged(next);
        }

        // 选项目是要去看它的对话：选完就收起，不用再点一次关闭。
        void pickProject(ConversationFilters next) {
          onChanged(next);
          Navigator.of(context).pop();
        }

        return AnimatedBuilder(
          animation: state,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: MobileSpace.lg),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: MobileSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionLabel(state.tr('范围', 'Location'), inset: 0),
                  SegmentBar<ConversationSource>(
                    values: const [
                      ConversationSource.all,
                      ConversationSource.local,
                      ConversationSource.remote,
                    ],
                    selected: draft.source,
                    label: (value) => sourceLabel(state, value),
                    onSelected: (value) {
                      final next = draft.copyWith(source: value);
                      // A project of another 范围 would leave nothing to show.
                      final key = next.projectKey;
                      pick(
                        key != null && !next.sourceMatches(key.$2)
                            ? next.copyWith(clearProject: true)
                            : next,
                      );
                    },
                  ),
                  SectionLabel(state.tr('排序', 'Sort'), inset: 0),
                  SegmentBar<ConversationSort>(
                    values: ConversationSort.values,
                    selected: draft.sort,
                    label: (value) => value == ConversationSort.recent
                        ? state.tr('最近活动', 'Recent activity')
                        : state.tr('名称', 'Name'),
                    onSelected: (value) => pick(draft.copyWith(sort: value)),
                  ),
                  SectionLabel(state.tr('状态', 'Status'), inset: 0),
                  SegmentBar<ConversationStatus>(
                    values: ConversationStatus.values,
                    selected: draft.status,
                    label: (value) => switch (value) {
                      ConversationStatus.all => state.tr('全部', 'All'),
                      ConversationStatus.active => state.tr('进行中', 'Active'),
                      ConversationStatus.pinned => state.tr('已置顶', 'Pinned'),
                    },
                    onSelected: (value) => pick(draft.copyWith(status: value)),
                  ),
                  SectionLabel(state.tr('分组', 'Group by'), inset: 0),
                  SegmentBar<ConversationGrouping>(
                    key: const ValueKey('conversation-grouping'),
                    values: ConversationGrouping.values,
                    selected: draft.grouping,
                    label: (value) => switch (value) {
                      ConversationGrouping.project => state.tr('项目', 'Project'),
                      ConversationGrouping.date => state.tr('日期', 'Date'),
                      ConversationGrouping.status => state.tr('状态', 'Status'),
                    },
                    onSelected: (value) => pick(draft.copyWith(grouping: value)),
                  ),
                  if (draft.grouping == ConversationGrouping.date)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        state.tr('按对话最近更新日期分组', 'Grouped by the last update date'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (projectSelection) ...[
                    SectionLabel(state.tr('只看项目', 'Project'), inset: 0),
                    _ProjectOption(
                      title: state.tr('全部项目', 'All projects'),
                      selected: draft.projectKey == null,
                      onTap: () =>
                          pickProject(draft.copyWith(clearProject: true)),
                    ),
                  ],
                  if (projectSelection && draft.projectKey != null &&
                      !state.projects.any(
                        (p) => (p.desktopId, p.project.id) == draft.projectKey,
                      ))
                    _ProjectOption(
                      title: state.tr(
                        '已选项目当前不可用',
                        'Selected project unavailable',
                      ),
                      selected: true,
                      onTap: () =>
                          pickProject(draft.copyWith(clearProject: true)),
                    ),
                  // Only the projects in the chosen 范围.
                  for (final ref in state.projects.where(
                    (ref) =>
                        projectSelection &&
                        ref.desktopId == state.selectedDesktopId &&
                        draft.sourceMatches(ref.project.id),
                  ))
                    _ProjectOption(
                      title: ref.project.name,
                      tag: switch (projectSource(ref.project.id)) {
                        ConversationSource.ssh => 'SSH',
                        ConversationSource.wsl => 'WSL',
                        _ => null,
                      },
                      selected:
                          draft.projectKey == (ref.desktopId, ref.project.id),
                      onTap: () => pickProject(
                        draft.copyWith(
                          projectKey: (ref.desktopId, ref.project.id),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _ProjectOption extends StatelessWidget {
  const _ProjectOption({
    required this.title,
    required this.selected,
    required this.onTap,
    this.tag,
  });
  final String title;
  final String? tag;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = MobileTheme.statusColorsOf(context);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.surfaceContainerHighest : Colors.transparent,
        borderRadius: BorderRadius.circular(MobileSizes.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(MobileSizes.radius),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: MobileSizes.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.folder_open_outlined
                        : Icons.folder_outlined,
                    size: 22,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (tag != null)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: status.info.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tag!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: status.info,
                        ),
                      ),
                    ),
                  if (selected) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.check_rounded,
                      size: 22,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
