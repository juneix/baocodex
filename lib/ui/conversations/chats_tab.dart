import 'dart:async';

import 'package:bao_link/bao_link.dart' show BotStatus;
import 'package:clock/clock.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'conversation_filters.dart';
import 'conversation_filter_sheet.dart';
import 'project_actions.dart';
import 'session_press_row.dart';

import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../../link/chat_codec.dart';
import '../../link/phone_link.dart' show DesktopLinkStatus;
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../tasks/chat_page.dart';
import '../bots/bots_tab.dart';
import '../devices/device_menu.dart';
import '../devices/devices_page.dart';
import '../files/files_tab.dart';
import '../settings/settings_page.dart';
import '../widgets/lucide_icon.dart';
import '../widgets/mobile_widgets.dart';
import '../widgets/model_icon.dart';
import '../widgets/bottom_sheet_panel.dart';
import '../widgets/project_icon_view.dart';
import '../widgets/formats.dart';

/// A new conversation, as the desktop's own starts one: in the project
/// used last on that desktop unless [project] is given, the page open at
/// once; the project can be changed there until the first message.
Future<void> newConversation(
  BuildContext context,
  AppState state, {
  ProjectRef? project,
  String? desktopId,
}) async {
  project ??= _recentProject(state, desktopId ?? state.selectedDesktopId);
  if (project == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          state.tr(
            '先在电脑中打开项目并连接。',
            'Connect a desktop with an open project first.',
          ),
        ),
      ),
    );
    return;
  }
  await _openNewConversation(context, state, project);
}

/// 上次选择的项目，其次是当前电脑最近的项目；离线时也可保留输入。
ProjectRef? _recentProject(AppState state, String? desktopId) {
  final selected = desktopId ?? state.selectedDesktopId;
  final projects = [
    for (final ref in state.projects)
      if (ref.desktopId == selected) ref,
  ];
  if (projects.isEmpty) return null;
  final remembered = state.settings.lastProjectByDesktop[selected];
  final previous = projects
      .where((ref) => ref.project.id == remembered)
      .firstOrNull;
  if (previous != null) return previous;
  final sessions = [
    for (final ref in state.sessions)
      if (projects.any(
        (p) =>
            p.desktopId == ref.desktopId && p.project.id == ref.session.project,
      ))
        ref,
  ]..sort((a, b) => b.session.updatedAt.compareTo(a.session.updatedAt));
  if (sessions.firstOrNull case final latest?) {
    return projects.firstWhere(
      (p) =>
          p.desktopId == latest.desktopId &&
          p.project.id == latest.session.project,
    );
  }
  return projects.first;
}

/// 先打开本地输入，只有发送或配置会话才向电脑创建草稿。
Future<void> _openNewConversation(
  BuildContext context,
  AppState state,
  ProjectRef project, {
  bool replace = false,
}) => runUi(context, () async {
  await state.rememberProject(project);
  if (!context.mounted) return;
  final page = ChatPage(
    state: state,
    desktopId: project.desktopId,
    title: state.tr('新对话', 'New conversation'),
    projectId: project.project.id,
    onSwitchProject: (pageContext) async {
      final next = await pickProject(pageContext, state, current: project);
      if (next == null ||
          (next.desktopId == project.desktopId &&
              next.project.id == project.project.id) ||
          !pageContext.mounted) {
        return;
      }
      await _openNewConversation(pageContext, state, next, replace: true);
    },
  );
  final route = MaterialPageRoute<void>(builder: (_) => page);
  if (replace) {
    await Navigator.of(context).pushReplacement(route);
  } else {
    await Navigator.of(context).push(route);
  }
});

/// The projects of [current]'s desktop to start a conversation in, from the
/// bottom: each with its folder and path, [current] ticked.
Future<ProjectRef?> pickProject(
  BuildContext anchor,
  AppState state, {
  required ProjectRef current,
}) => showBottomSheetPanel<ProjectRef>(
  anchor,
  title: state.tr('选择项目', 'Choose project'),
  closeLabel: state.tr('关闭', 'Close'),
  size: SheetSize.medium,
  builder: (context) {
    final theme = Theme.of(context);
    final choices = [
      for (final ref in state.projects)
        if (ref.desktopId == current.desktopId) ref,
    ];
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          MobileSpace.sm,
          0,
          MobileSpace.sm,
          MobileSpace.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final ref in choices)
              Builder(
                builder: (context) {
                  final selected = ref.project.id == current.project.id;
                  return Material(
                    color: selected
                        ? theme.colorScheme.surfaceContainerHighest
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(MobileSizes.radius),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      key: ValueKey('pick-project-${ref.project.id}'),
                      leading: const LucideIcon('folder', size: 22),
                      title: Text(
                        ref.project.name,
                        style: selected
                            ? const TextStyle(fontWeight: FontWeight.w600)
                            : null,
                      ),
                      subtitle: Text(
                        ref.project.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: selected
                          ? LucideIcon(
                              'check',
                              size: 20,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      onTap: () => Navigator.pop(context, ref),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  },
);

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key, required this.state});
  final AppState state;
  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  ConversationFilters _filters = const ConversationFilters();
  final _search = TextEditingController();
  final _scaffold = GlobalKey<ScaffoldState>();
  final _collapsed = <(String, String, String)>{};
  final _showAll = <(String, String, String)>{};
  Timer? _timeTimer;
  String? _desktopId, _entryProjectId;
  ({String desktop, String project, String session, String title})?
      _conversation;
  Object _pageKey = Object();
  bool _new = true;

  @override
  void initState() {
    super.initState();
    _desktopId = widget.state.selectedDesktopId;
    _entryProjectId = _recentProject(widget.state, _desktopId)?.project.id;
    widget.state.addListener(_workspaceChanged);
  }

  @override
  void didUpdateWidget(ChatsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_workspaceChanged);
      widget.state.addListener(_workspaceChanged);
      _desktopId = null;
      _entryProjectId = null;
      _conversation = null;
      _new = true;
      _pageKey = Object();
      _workspaceChanged();
    }
  }

  void _workspaceChanged() {
    if (!mounted) return;
    setState(() {
      final desktop = widget.state.selectedDesktopId;
      if (desktop != _desktopId) {
        _desktopId = desktop;
        _entryProjectId = null;
        _conversation = null;
        _new = true;
        _pageKey = Object();
        _filters = const ConversationFilters();
        _search.clear();
      }
      // 活动排序和重连刷新不能把正在输入的任务悄悄换到其他项目。
      _entryProjectId ??= _recentProject(widget.state, desktop)?.project.id;
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(_workspaceChanged);
    _timeTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _clearFilters() => setState(() {
    _filters = const ConversationFilters();
    _search.clear();
  });

  void _openNavigation() => _scaffold.currentState?.openDrawer();

  void _drawerChanged(bool open) {
    _timeTimer?.cancel();
    _timeTimer = open
        ? Timer.periodic(const Duration(minutes: 1), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  void _toggleGroup((String, String, String) key) => setState(() {
    if (!_collapsed.remove(key)) _collapsed.add(key);
  });

  void _showNew([ProjectRef? project, bool closeDrawer = true]) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _conversation = null;
      _entryProjectId = project?.project.id ??
          _recentProject(widget.state, _desktopId)?.project.id;
      _new = true;
      _pageKey = Object();
      if (project != null) {
        _collapsed.remove(('project', project.desktopId, project.project.id));
      }
    });
    if (project != null) {
      unawaited(runUi(context, () => widget.state.rememberProject(project)));
    }
    if (closeDrawer) _scaffold.currentState?.closeDrawer();
  }

  void _showSession(SessionRef ref) {
    FocusManager.instance.primaryFocus?.unfocus();
    final current = _conversation;
    if (current?.desktop != ref.desktopId ||
        current?.session != ref.session.id) {
      setState(() {
        _new = false;
        _pageKey = Object();
        _conversation = (
          desktop: ref.desktopId,
          project: ref.session.project,
          session: ref.session.id,
          title: ref.session.title,
        );
      });
      final project = widget.state.projects
          .where((p) => p.desktopId == ref.desktopId &&
              p.project.id == ref.session.project)
          .firstOrNull;
      if (project != null) {
        unawaited(runUi(context, () => widget.state.rememberProject(project)));
      }
    }
    _scaffold.currentState?.closeDrawer();
  }

  void _created(Object key, String desktop, String project, String session) {
    if (!mounted || !identical(key, _pageKey) || _desktopId != desktop) return;
    setState(() => _conversation = (
      desktop: desktop,
      project: project,
      session: session,
      title: widget.state.tr('新对话', 'New conversation'),
    ));
  }

  void _back() {
    if (_scaffold.currentState?.isDrawerOpen == true) {
      _scaffold.currentState?.closeDrawer();
    } else {
      _showNew();
    }
  }

  void _openDestination(Widget page) {
    _scaffold.currentState?.closeDrawer();
    openPage<void>(context, page);
  }

  void _openFiles(ProjectRef? project) => _openDestination(
    project != null && widget.state.isOnline(project.desktopId)
        ? FilesPage(state: widget.state, project: project)
        : FilesTab(state: widget.state),
  );

  List<_SessionGroup> _sessionGroups(List<ConversationProject> projects) {
    final state = widget.state;
    if (_filters.grouping == ConversationGrouping.project) return const [];
    final unique = <(String, String), SessionRef>{
      for (final project in projects)
        for (final ref in project.sessions)
          (ref.desktopId, ref.session.id): ref,
    };
    final sessions = _filters.copyWith(query: '').sessions(
      unique.values,
      state.desktopName,
    );
    final buckets = <String, List<SessionRef>>{};
    final now = clock.now().toLocal();
    final today = DateTime.utc(now.year, now.month, now.day);
    for (final ref in sessions) {
      final String key;
      if (_filters.grouping == ConversationGrouping.status) {
        key = ref.session.status.name;
      } else {
        final date = ref.session.updatedAt.toLocal();
        final days = today
            .difference(DateTime.utc(date.year, date.month, date.day))
            .inDays;
        key = days <= 0
            ? 'today'
            : days == 1
            ? 'yesterday'
            : days < 7
            ? 'week'
            : 'earlier';
      }
      buckets.putIfAbsent(key, () => []).add(ref);
    }
    final order = _filters.grouping == ConversationGrouping.status
        ? const ['needsInput', 'running', 'idle']
        : const ['today', 'yesterday', 'week', 'earlier'];
    return [
      for (final key in order)
        if (buckets[key] case final rows?)
          _SessionGroup(
            key,
            switch (key) {
              'needsInput' => state.tr('等待回应', 'Needs input'),
              'running' => state.tr('运行中', 'Running'),
              'idle' => state.tr('空闲', 'Idle'),
              'today' => state.tr('今天', 'Today'),
              'yesterday' => state.tr('昨天', 'Yesterday'),
              'week' => state.tr('最近七天', 'Last seven days'),
              _ => state.tr('更早', 'Earlier'),
            },
            _filters.grouping == ConversationGrouping.date ? 'calendar-days' : 'clock',
            rows,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final desktopId = state.selectedDesktopId;
    final projects = _filters.projects(
      state.projects.where((ref) => ref.desktopId == desktopId),
      state.sessions,
      state.desktopName,
    );
    // 所有 Bot 都在首页有一行，不只是助理：自己加的那些也能直接点开聊。
    final bots = _filters.allowsBots
        ? state.bots
              .where(
                (b) =>
                    b.desktopId == desktopId &&
                    '${b.bot.name} ${b.bot.last ?? ''}'.toLowerCase().contains(
                      _filters.query.trim().toLowerCase(),
                    ),
              )
              .toList()
        : <BotRef>[];
    final current = _conversation;
    final project = state.projects
        .where((p) => p.desktopId == (current?.desktop ?? desktopId) &&
            p.project.id == (current?.project ?? _entryProjectId))
        .firstOrNull;
    final key = _pageKey;
    final targetDesktop = current?.desktop ?? desktopId;
    final targetProject = current?.project ?? _entryProjectId;
    final groups = _sessionGroups(projects);
    final keys = <(String, String, String)>[
      if (_filters.grouping == ConversationGrouping.project)
        for (final item in projects)
          ('project', item.ref.desktopId, item.ref.project.id)
      else
        for (final group in groups)
          (_filters.grouping.name, desktopId ?? '', group.id),
      for (final ref in bots) ('bot', ref.desktopId, ref.bot.id),
    ];
    final expanded = keys.isNotEmpty && keys.every((key) => !_collapsed.contains(key));
    return Scaffold(
      key: _scaffold,
      resizeToAvoidBottomInset: false,
      drawerEdgeDragWidth: 24,
      onDrawerChanged: _drawerChanged,
      drawer: Drawer(
        key: const ValueKey('conversation-drawer'),
        width: MediaQuery.sizeOf(context).width * .8,
        // 侧栏和对话页同一层灰，白底胶囊才立得住。
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          minimum: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    // 标题左边的小 logo。
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SvgPicture.asset(
                        'assets/icons/baocodex.svg',
                        key: const ValueKey('drawer-logo'),
                        width: 24,
                        height: 24,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'BaoCodeX',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 白底胶囊里的新对话，和顶栏一致。
                    Material(
                      color: Theme.of(context).colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(999),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: const ValueKey('drawer-new-conversation'),
                        onTap: () => _showNew(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const LucideIcon('message-circle-plus', size: 18),
                              const SizedBox(width: 6),
                              Text(state.tr('新对话', 'New chat')),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SearchCapsule(
                state: state,
                controller: _search,
                outlined: true,
                hint: state.tr('搜索对话', 'Search conversations'),
                onChanged: (value) => setState(
                  () => _filters = _filters.copyWith(query: value),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.tr('工作区', 'Workspaces'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('toggle-all-groups'),
                      tooltip: expanded
                          ? state.tr('收起全部', 'Collapse all')
                          : state.tr('展开全部', 'Expand all'),
                      // 工作区标题旁的按钮不套白底，只保留图标。
                      style: _plainButton(context),
                      icon: LucideIcon(
                        expanded ? 'folder-minus' : 'folder-plus',
                        size: 20,
                      ),
                      onPressed: keys.isEmpty
                          ? null
                          : () => setState(() {
                              if (expanded) {
                                _collapsed.addAll(keys);
                              } else {
                                _collapsed.removeAll(keys);
                              }
                            }),
                    ),
                    Builder(
                      builder: (anchor) => IconButton(
                        tooltip: state.tr('筛选对话', 'Filter conversations'),
                        style: _plainButton(context),
                        icon: const LucideIcon('list-sort-descending', size: 20),
                        onPressed: () => showConversationFilters(
                          anchor,
                          state,
                          _filters,
                          (selected) {
                            if (mounted) {
                              setState(() => _filters = selected);
                            }
                          },
                          projectSelection: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_filters.restricted)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          filterSummary(state, _filters),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: _clearFilters,
                        // 与「展开剩余」同字号、同主题色，右缘与列表对齐。
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 0,
                            vertical: 8,
                          ),
                          minimumSize: const Size(0, 36),
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          textStyle: MobileTheme.hintStyleOf(context),
                        ),
                        child: Text(state.tr('清除', 'Clear')),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView(
                  key: const ValueKey('conversation-navigation-list'),
                  children: [
                    ..._navigationRows(projects, bots, groups),
                    if (projects.isEmpty && bots.isEmpty)
                      _emptyNote(state, desktopId),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: DesktopSwitcherTitle(
                        state: state,
                        onChanged: _clearFilters,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('drawer-bots'),
                      tooltip: state.tr('Bot 管理', 'Manage bots'),
                      style: _softButton(context),
                      icon: const LucideIcon('bot', size: 20),
                      onPressed: () => _openDestination(BotsTab(state: state)),
                    ),
                    const SizedBox(width: MobileSpace.sm),
                    IconButton(
                      key: const ValueKey('drawer-settings'),
                      tooltip: state.tr('设置', 'Settings'),
                      style: _softButton(context),
                      icon: const LucideIcon('settings', size: 20),
                      onPressed: () => _openDestination(SettingsPage(state: state)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: targetDesktop != null && targetProject != null
          ? ChatPage(
              key: ValueKey(key),
              state: state,
              desktopId: targetDesktop,
              projectId: targetProject,
              sessionId: current?.session,
              title: state.sessions
                      .where((ref) => ref.desktopId == current?.desktop &&
                          ref.session.id == current?.session)
                      .firstOrNull?.session.title ??
                  current?.title ?? state.tr('新对话', 'New conversation'),
              projectUnavailable: project == null,
              onOpenNavigation: _openNavigation,
              onNewConversation: () => _showNew(),
              onCloseConversation: current == null ? null : _back,
              onSessionCreated: (session) =>
                  _created(key, targetDesktop, targetProject, session),
              onSwitchProject: _new && project != null
                  ? (anchor) async {
                      final selected = await pickProject(
                        anchor,
                        state,
                        current: project,
                      );
                      if (!mounted || selected == null ||
                          selected.desktopId != _desktopId ||
                          selected.project.id == project.project.id) {
                        return;
                      }
                      _showNew(selected, false);
                    }
                  : null,
            )
          : Scaffold(
              appBar: AppBar(
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.tr('新对话', 'New conversation')),
                    Text(
                      desktopId == null
                          ? state.tr('未连接电脑', 'No computer connected')
                          : '${state.desktopName(desktopId)} · ${linkStatusLabel(state, state.linkStatus(desktopId))}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                leading: IconButton(
                  tooltip: state.tr('打开菜单', 'Open menu'),
                  icon: const LucideIcon('menu', size: 22),
                  onPressed: _openNavigation,
                ),
                actions: [
                  IconButton(
                    tooltip: state.tr('新对话', 'New conversation'),
                    icon: const LucideIcon('message-circle-plus', size: 22),
                    onPressed: targetProject == null ? null : () => _showNew(),
                  ),
                  IconButton(
                    key: const ValueKey('chat-open-files'),
                    tooltip: state.tr('文件', 'Files'),
                    icon: const LucideIcon('folder', size: 22),
                    onPressed: () => _openFiles(null),
                  ),
                ],
              ),
              body: state.desktops.isEmpty
                  ? EmptyPanel(
                      state.tr('连接电脑，开始编程任务。',
                          'Connect a desktop to start coding.'),
                      actionLabel: state.tr('配对新电脑', 'Pair a desktop'),
                      onAction: () => openPage<void>(
                        context, PairDevicePage(state: state)),
                    )
                  : _emptyNote(state, desktopId, filtered: false),
            ),
    );
  }

  /// 侧栏里次要按钮的白色圆形浮层：灰底页面上才立得住。
  /// 标题旁的次要图标：不套白底。
  static ButtonStyle _plainButton(BuildContext context) =>
      IconButton.styleFrom(
        fixedSize: const Size.square(MobileSizes.iconButton),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  static ButtonStyle _softButton(BuildContext context) =>
      IconButton.styleFrom(
        fixedSize: const Size.square(MobileSizes.iconButton),
        padding: EdgeInsets.zero,
        // 点击区域不再外扩，圆的边长就是布局宽度，右缘才和搜索框、时间对齐。
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      );

  Widget _sessionRow(AppState state, SessionRef ref) => projectSessionRow(
    context,
    state,
    ref,
    key: ValueKey('session-${ref.desktopId}-${ref.session.id}'),
    compact: true,
    selected: _conversation?.desktop == ref.desktopId &&
        _conversation?.session == ref.session.id,
    divider: false,
    onTap: () => _showSession(ref),
  );

  Widget _projectRow(AppState state, ConversationProject item) {
    final ref = item.ref;
    final sessions = item.sessions;
    final key = ('project', ref.desktopId, ref.project.id);
    final collapsed = _collapsed.contains(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProjectActionRow(
          key: ValueKey('project-${ref.desktopId}-${ref.project.id}'),
          state: state,
          project: ref,
          child: ListRow(
            key: ValueKey('project-fold-${ref.desktopId}-${ref.project.id}'),
            compact: true,
            titleBold: false,
            divider: false,
            leading: waitingAvatar(
              state,
              ProjectIconView(state: state, ref: ref, size: 22),
              sessions,
            ),
            title: projectRowTitle(ref),
            aside: ref.project.pinned == true
                ? const LucideIcon('pin', size: 16)
                : null,
            // 尾部元素不再自带左右留白：右缘和搜索框、时间同一条边线。
            trailing: collapsed
                ? Text(
                    '${sessions.length}',
                    key: ValueKey(
                      'project-count-${ref.desktopId}-${ref.project.id}',
                    ),
                  )
                : IconButton(
                    key: ValueKey(
                      'project-new-${ref.desktopId}-${ref.project.id}',
                    ),
                    tooltip: state.tr('新对话', 'New conversation'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const LucideIcon('plus', size: 20),
                    onPressed: () => _showNew(ref),
                  ),
            onTap: () => _toggleGroup(key),
          ),
        ),
        // 折叠时给这一组一条分割线，左右与搜索框、时间同一条边线。
        if (collapsed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(
              height: 1,
              key: ValueKey('project-divider-${ref.desktopId}-${ref.project.id}'),
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        if (!collapsed) ..._sessionChildren(key, sessions),
        if (!collapsed && sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 16, 12),
            child: Text(
              state.tr('还没有对话，直接开始新任务。',
                  'No conversations yet. Start a new task.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  List<Widget> _sessionChildren(
    (String, String, String) key,
    List<SessionRef> sessions,
  ) {
    final state = widget.state;
    final all = _showAll.contains(key);
    return [
      for (final ref in all ? sessions : sessions.take(5))
        _sessionRow(state, ref),
      if (sessions.length > 5)
        Padding(
          // 与搜索框、会话行同一条左边界。
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: ValueKey(
                '${key.$1 == 'project' ? 'project' : 'group'}-more-${key.$2}-${key.$3}',
              ),
              onPressed: () => setState(() {
                if (!_showAll.remove(key)) _showAll.add(key);
              }),
              // 和「按状态」「按更新日期」同一档字号，用主题金而不是绿色。
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 0,
                  vertical: 8,
                ),
                minimumSize: const Size(0, 36),
                foregroundColor: Theme.of(context).colorScheme.primary,
                textStyle: MobileTheme.hintStyleOf(context),
              ),
              child: Text(
                all
                    ? state.tr('收起过多对话', 'Show fewer conversations')
                    : state.tr('展开剩余 ${sessions.length - 5} 条',
                        'Show ${sessions.length - 5} more'),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _sessionGroupRow(
    (String, String, String) key,
    String title,
    String icon,
    List<SessionRef> sessions,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListRow(
        key: ValueKey('conversation-group-${key.$1}-${key.$3}'),
        compact: true,
        titleBold: false,
        divider: false,
        leading: LucideIcon(icon, size: 22),
        title: title,
        trailing: Text('${sessions.length}'),
        onTap: () => _toggleGroup(key),
      ),
      if (!_collapsed.contains(key))
        ..._sessionChildren(key, sessions),
    ],
  );

  Widget _botGroupRow(BotRef ref) {
    final state = widget.state;
    final key = ('bot', ref.desktopId, ref.bot.id);
    final collapsed = _collapsed.contains(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BotPressRow(
          state: state,
          ref: ref,
          child: ListRow(
            key: ValueKey('bot-fold-${ref.desktopId}-${ref.bot.id}'),
            compact: true,
            titleBold: false,
            divider: false,
            leading: Badge(
              isLabelVisible: ref.bot.unread > 0,
              label: Text('${ref.bot.unread}'),
              child: const LucideIcon('bot', size: 22),
            ),
            title: ref.bot.name,
            trailing: collapsed ? const Text('1') : null,
            onTap: () => _toggleGroup(key),
          ),
        ),
        if (!collapsed)
          _BotChatRow(
            key: ValueKey('bot-${ref.desktopId}-${ref.bot.id}'),
            state: state,
            ref: ref,
            onTap: () => _openDestination(
              ChatPage(
                state: state,
                desktopId: ref.desktopId,
                sessionId: ref.bot.session ?? 'bot:${ref.bot.id}',
                title: ref.bot.name,
                botId: ref.bot.id,
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _navigationRows(
    List<ConversationProject> projects,
    List<BotRef> bots,
    List<_SessionGroup> groups,
  ) {
    final state = widget.state;
    final order = {for (final (index, ref) in bots.indexed) ref.bot.id: index};
    final orderedBots = List.of(bots)..sort((a, b) {
      final pin = (state.botPinned(b) ? 1 : 0) - (state.botPinned(a) ? 1 : 0);
      if (pin != 0) return pin;
      final at = a.bot.updatedAt, bt = b.bot.updatedAt;
      if ((at == null) != (bt == null)) return at == null ? 1 : -1;
      if (at != null && bt != null && at != bt) return bt.compareTo(at);
      return order[a.bot.id]!.compareTo(order[b.bot.id]!);
    });
    return [
      if (_filters.grouping == ConversationGrouping.project)
        for (final item in projects) _projectRow(state, item)
      else
        for (final group in groups)
          _sessionGroupRow(
            (_filters.grouping.name, state.selectedDesktopId ?? '', group.id),
            group.title,
            group.icon,
            group.sessions,
          ),
      for (final ref in orderedBots) _botGroupRow(ref),
    ];
  }

  /// Why the list is empty: still connecting, offline, a filter, or no
  /// project open on that desktop.
  Widget _emptyNote(AppState state, String? desktopId, {bool filtered = true}) {
    final name = desktopId == null ? '' : state.desktopName(desktopId);
    final status = desktopId == null ? null : state.linkStatus(desktopId);
    final (text, retry) = switch (status) {
      _ when filtered && _filters.restricted => (
        state.tr('没有匹配的项目或会话', 'No matching projects or conversations'),
        false,
      ),
      DesktopLinkStatus.connecting => (
        state.tr('正在连接 $name…', 'Connecting to $name…'),
        false,
      ),
      DesktopLinkStatus.offline => (
        '$name ${linkStatusLabel(state, DesktopLinkStatus.offline)}',
        true,
      ),
      DesktopLinkStatus.needsPairing => (
        '$name ${linkStatusLabel(state, DesktopLinkStatus.needsPairing)}',
        false,
      ),
      _ => (state.tr('电脑上还没有打开的项目', 'No projects open on this desktop'), false),
    };
    return Padding(
      padding: const EdgeInsets.all(MobileSpace.xl),
      child: Column(
        children: [
          if (status == DesktopLinkStatus.connecting) ...[
            ConnectingSpinner(
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: MobileSpace.md),
          ],
          Text(
            text,
            textAlign: TextAlign.center,
            // 需重新配对是唯一要动手的，红；其余是说明，灰。
            style: TextStyle(
              color: status == DesktopLinkStatus.needsPairing
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).hintColor,
            ),
          ),
          if (retry && desktopId != null)
            TextButton(
              onPressed: () => state.retryConnection(desktopId),
              child: Text(state.tr('重试', 'Retry')),
            ),
        ],
      ),
    );
  }

}

class _SessionGroup {
  const _SessionGroup(this.id, this.title, this.icon, this.sessions);
  final String id, title, icon;
  final List<SessionRef> sessions;
}

class _BotChatRow extends StatelessWidget {
  const _BotChatRow({
    super.key,
    required this.state,
    required this.ref,
    required this.onTap,
  });
  final AppState state;
  final BotRef ref;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => BotPressRow(
    state: state,
    ref: ref,
    child: ListRow(
      compact: true,
      titleBold: false,
      leading: Center(
        child: Tooltip(
          message: ref.bot.status == BotStatus.typing
              ? state.tr('正在输入', 'Typing')
              : state.tr('Bot 对话', 'Bot conversation'),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ref.bot.status == BotStatus.typing && state.isOnline(ref.desktopId)
                  ? MobileTheme.statusColorsOf(context).success
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      title: ref.bot.last?.trim().isNotEmpty == true
          ? ref.bot.last!
          : state.tr('与 ${ref.bot.name} 对话', 'Chat with ${ref.bot.name}'),
      time: switch (ref.bot.updatedAt) {
        final at? => _sessionTime(state, at),
        null => null,
      },
      trailing: state.botPinned(ref) ? const LucideIcon('pin', size: 16) : null,
      onTap: onTap,
    ),
  );
}

class ProjectChatsPage extends StatelessWidget {
  const ProjectChatsPage({
    super.key,
    required this.state,
    required this.project,
    this.filters = const ConversationFilters(),
  });
  final AppState state;
  final ProjectRef project;
  final ConversationFilters filters;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final sessions = filters.sessions(
        state.sessions.where(
          (s) =>
              s.desktopId == project.desktopId &&
              s.session.project == project.project.id,
        ),
        state.desktopName,
        projectName: project.project.name,
      );
      return Scaffold(
        appBar: AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                project.project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // What the rows show is only last known until it reconnects.
              if (!state.isOnline(project.desktopId))
                Text(
                  devicePathText(state, project.desktopId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: state.isOnline(project.desktopId)
                  ? state.tr('项目文件', 'Project files')
                  : state.tr(
                      '电脑已断开，无法查看项目文件',
                      'Desktop offline; project files unavailable',
                    ),
              icon: const LucideIcon('folder', size: 22),
              onPressed: state.isOnline(project.desktopId)
                  ? () => openPage<void>(
                      context,
                      FilesPage(state: state, project: project),
                    )
                  : null,
            ),
            IconButton(
              tooltip: state.tr('新对话', 'New conversation'),
              icon: const LucideIcon('square-pen', size: 22),
              onPressed: () =>
                  newConversation(context, state, project: project),
            ),
          ],
        ),
        body: Column(
          children: [
            if (filters.restricted)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  filterSummary(state, filters),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Expanded(
              child: sessions.isEmpty
                  ? EmptyPanel(
                      state.tr('还没有对话', 'No conversations yet'),
                      actionLabel: state.tr('新对话', 'New conversation'),
                      onAction: () =>
                          newConversation(context, state, project: project),
                    )
                  : ListView.builder(
                      itemCount: sessions.length,
                      itemBuilder: (context, index) =>
                          projectSessionRow(context, state, sessions[index]),
                    ),
            ),
          ],
        ),
      );
    },
  );
}

/// 侧栏里的项目标题：远程项目写成「用户名 · 设备名」，本地就是文件夹名。
String projectRowTitle(ProjectRef ref) {
  final id = ref.project.id;
  if (!id.startsWith('ssh://')) return ref.project.name;
  final rest = id.substring(6);
  final slash = rest.indexOf('/');
  if (slash <= 0) return ref.project.name;
  final host = rest.substring(0, slash);
  if (host.startsWith('wsl+')) return ref.project.name;
  final at = host.indexOf('@');
  if (at <= 0 || at == host.length - 1) return host;
  return '${host.substring(0, at)} · ${host.substring(at + 1)}';
}

/// A conversation in a project's list: in the project's page, the home list
/// filtered to the project, and under a project unfolded there.
Widget projectSessionRow(
  BuildContext context,
  AppState state,
  SessionRef ref, {
  Key? key,
  VoidCallback? onTap,
  bool compact = false,
  bool selected = false,
  bool divider = true,
}) {
  final flags = statusFlags(context, state, [ref], counted: false);
  return SessionPressRow(
    key: key ?? ValueKey('session-${ref.desktopId}-${ref.session.id}'),
    state: state,
    session: ref,
    child: ListRow(
      compact: compact,
      titleBold: false,
      highlighted: selected,
      divider: divider,
      leading: compact
          ? Center(
              // 状态小圆点，按状态换颜色；选中的更实一点。
              child: Tooltip(
                message: !state.isOnline(ref.desktopId)
                    ? linkStatusLabel(state, state.linkStatus(ref.desktopId))
                    : flags.firstOrNull?.$1 ?? state.tr('空闲', 'Idle'),
                child: Container(
                  width: selected ? 9 : 7,
                  height: selected ? 9 : 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: flags.firstOrNull?.$2 ??
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : waitingAvatar(state, LetterAvatar(ref.session.title), [ref]),
      title: ref.session.title,
      note: null,
      aside: compact ? null : modelTag(context, state, ref),
      flags: compact ? const [] : flags,
      subtitle: compact ? null : lastLine(state, ref),
      time: _sessionTime(state, ref.session.updatedAt),
      status: compact
          ? null
          : ref.session.pinned
          ? const LucideIcon('pin', size: 16)
          : null,
      trailing: !compact
          ? null
          : ref.session.pinned
          ? const LucideIcon('pin', size: 16)
          : null,
      onTap: onTap ?? () => openPage<void>(
        context,
        ChatPage(
          state: state,
          desktopId: ref.desktopId,
          sessionId: ref.session.id,
          title: ref.session.title,
          projectId: ref.session.project,
        ),
      ),
    ),
  );
}

/// [avatar] with how many of [sessions] wait on the user (needing an answer,
/// or done and not looked at) on its corner, as chat apps mark a chat:
/// counted as the 对话 tab counts them, so the list's marks add up to it.
Widget waitingAvatar(
  AppState state,
  Widget avatar,
  Iterable<SessionRef> sessions,
) {
  final counts = state.countByStatus(sessions);
  final waiting = counts.needsInput + counts.done;
  return Badge(
    isLabelVisible: waiting > 0,
    label: Text('$waiting'),
    offset: const Offset(6, -6),
    child: avatar,
  );
}

String _sessionTime(AppState state, DateTime date, [DateTime? now]) =>
    relativeTimeText(state, date, now: now);

/// 「2 个运行中 · 1 个待处理」 for a project, 「运行中」 for one conversation:
/// the same words wherever a status shows. Nothing while the desktop is not
/// connected, what it last said being stale; its title says so instead.
List<(String, Color)> statusFlags(
  BuildContext context,
  AppState state,
  Iterable<SessionRef> sessions, {
  bool counted = true,
}) {
  final colors = Theme.of(context).colorScheme;
  // 电脑离线时它最后说的状态已经过时：那时不标，标题上写着离线。
  final (running: running, needsInput: waiting, done: done) = state
      .countByStatus(sessions.where((ref) => state.isOnline(ref.desktopId)));
  return [
    if (running > 0)
      (
        counted
            ? state.tr('$running 个运行中', '$running running')
            : state.tr('运行中', 'Running'),
        // Under way is indigo whatever the accent, apart from green (done).
        MobileTheme.statusColorsOf(context).info,
      ),
    if (waiting > 0)
      (
        counted
            ? state.tr('$waiting 个待处理', '$waiting need input')
            : state.tr('待处理', 'Needs input'),
        colors.error,
      ),
    if (done > 0)
      (
        counted
            ? state.tr('$done 个已完成', '$done done')
            : state.tr('已完成', 'Done'),
        MobileTheme.statusColorsOf(context).success,
      ),
  ];
}

/// The last thing the agent said in a conversation, from the cached buffer;
/// null when it was never opened here. Never subscribes.
String? lastLine(AppState state, SessionRef ref) {
  final buffer = state.peekBuffer(ref.desktopId, ref.session.id);
  for (final raw in buffer?.items.reversed ?? const <Map<String, Object?>>[]) {
    final item = ChatCodec.decode(raw);
    if (item is AssistantTextItem) {
      final text = oneLineExcerpt(item.text, max: 80);
      return text.isEmpty ? null : text;
    }
  }
  return null;
}

/// The model a conversation runs on, left of its time: its maker's logo and
/// name, as [AppState.sessionModel] knows it. Never subscribes.
Widget? modelTag(BuildContext context, AppState state, SessionRef ref) {
  final model = state.sessionModel(ref);
  if (model == null) return null;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ModelIcon.ofId(
        model.id,
        provider: model.provider,
        providerLabel: model.providerLabel,
        size: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 3),
      // 字号、颜色和截断跟着那一行的 [ListRow.aside]。
      Flexible(child: Text(modelShortName(model.id, model.label))),
    ],
  );
}
