import 'dart:async';

import 'package:bao_link/bao_link.dart';

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
import '../widgets/dropdown_panel.dart';
import '../widgets/lucide_icon.dart';
import '../widgets/mobile_widgets.dart';
import '../widgets/model_icon.dart';
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

/// The projects of [current]'s desktop to start a conversation in, beside
/// [anchor]: each with its folder and branch, [current] ticked.
Future<ProjectRef?> pickProject(
  BuildContext anchor,
  AppState state, {
  required ProjectRef current,
}) => showDropdownPanel<ProjectRef>(
  anchor,
  width: 640,
  builder: (context) {
    final theme = Theme.of(context);
    final choices = [
      for (final ref in state.projects)
        if (ref.desktopId == current.desktopId) ref,
    ];
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(MobileSpace.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final ref in choices)
              Builder(
                builder: (context) {
                  final selected = ref.project.id == current.project.id;
                  final branch = ref.project.branch;
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
                        [
                          ref.project.path,
                          if (branch != null && branch.isNotEmpty) branch,
                        ].join(' · '),
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
  const ChatsTab({
    super.key,
    required this.state,
    this.active = true,
    this.onSelectTab,
  });
  final AppState state;
  final bool active;
  final ValueChanged<int>? onSelectTab;
  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  ConversationFilters _filters = const ConversationFilters();
  final _search = TextEditingController();
  final _scaffold = GlobalKey<ScaffoldState>();
  final _collapsed = <(String, String)>{};
  final _showAll = <(String, String)>{};
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
    _search.dispose();
    super.dispose();
  }

  void _clearFilters() => setState(() {
    _filters = const ConversationFilters();
    _search.clear();
  });

  void _openNavigation() => _scaffold.currentState?.openDrawer();

  void _showNew([ProjectRef? project, bool closeDrawer = true]) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _conversation = null;
      _entryProjectId = project?.project.id ??
          _recentProject(widget.state, _desktopId)?.project.id;
      _new = true;
      _pageKey = Object();
      if (project != null) {
        _collapsed.remove((project.desktopId, project.project.id));
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

  void _openTab(int index) {
    _scaffold.currentState?.closeDrawer();
    final select = widget.onSelectTab;
    if (select != null) {
      select(index);
    } else {
      openPage<void>(context, switch (index) {
        1 => BotsTab(state: widget.state),
        2 => FilesTab(state: widget.state),
        _ => SettingsPage(state: widget.state),
      });
    }
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
    // Conversations put on the home list stand beside the projects; being
    // pinned only lifts one within its project (and, on the home list, to
    // the top).
    final home = state.sessions.where((ref) {
      if (ref.desktopId != desktopId || !state.onHome(ref)) return false;
      final project = state.projects
          .where(
            (p) =>
                p.desktopId == ref.desktopId &&
                p.project.id == ref.session.project,
          )
          .firstOrNull;
      return _filters
          .sessions(
            [ref],
            state.desktopName,
            projectName: project?.project.name ?? '',
          )
          .isNotEmpty;
    }).toList();
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
    return Scaffold(
      key: _scaffold,
      resizeToAvoidBottomInset: false,
      drawerEdgeDragWidth: 24,
      drawer: Drawer(
        key: const ValueKey('conversation-drawer'),
        width: (MediaQuery.sizeOf(context).width * .88)
            .clamp(0, 360)
            .toDouble(),
        child: SafeArea(
          minimum: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: DesktopSwitcherTitle(
                        state: state,
                        onChanged: _clearFilters,
                      ),
                    ),
                    IconButton(
                      tooltip: state.tr('关闭菜单', 'Close menu'),
                      icon: const LucideIcon('x', size: 22),
                      onPressed: () => _scaffold.currentState?.closeDrawer(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('drawer-new-conversation'),
                    onPressed: () => _showNew(),
                    icon: const LucideIcon('square-pen', size: 20),
                    label: Text(state.tr('新对话', 'New conversation')),
                  ),
                ),
              ),
              SearchCapsule(
                state: state,
                controller: _search,
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
                        _filters.restricted
                            ? filterSummary(state, _filters)
                            : state.tr('项目与对话', 'Projects and conversations'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (_filters.restricted)
                      TextButton(
                        onPressed: _clearFilters,
                        child: Text(state.tr('清除', 'Clear')),
                      ),
                    Builder(
                      builder: (anchor) => IconButton(
                        tooltip: state.tr('筛选对话', 'Filter conversations'),
                        icon: const LucideIcon('list-filter', size: 20),
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
              Expanded(
                child: ListView(
                  key: const ValueKey('conversation-navigation-list'),
                  children: [
                    ..._navigationRows(projects, bots, home),
                    if (projects.isEmpty && home.isEmpty && bots.isEmpty)
                      _emptyNote(state, desktopId),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => _openTab(1),
                      child: const Text('Bot'),
                    ),
                    TextButton(
                      onPressed: () => _openTab(2),
                      child: Text(state.tr('文件', 'Files')),
                    ),
                    TextButton(
                      onPressed: () => _openTab(3),
                      child: Text(state.tr('设置', 'Settings')),
                    ),
                    TextButton(
                      onPressed: () => openPage<void>(
                        context, BotEditPage(state: state)),
                      child: Text(state.tr('添加 Bot', 'Add bot')),
                    ),
                    TextButton(
                      onPressed: () => openPage<void>(
                        context, PairDevicePage(state: state)),
                      child: Text(state.tr('配对新电脑', 'Pair a desktop')),
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
              active: widget.active,
              projectUnavailable: project == null,
              onOpenNavigation: _openNavigation,
              onNewConversation: () => _showNew(),
              onCloseConversation: current == null ? null : _back,
              onSessionCreated: (session) =>
                  _created(key, targetDesktop, targetProject, session),
              onSwitchProject: _new
                  ? (_) async => _openNavigation()
                  : null,
            )
          : Scaffold(
              appBar: AppBar(
                title: DesktopSwitcherTitle(state: state),
                leading: IconButton(
                  tooltip: state.tr('项目与对话', 'Projects and conversations'),
                  icon: const Icon(Icons.menu, size: 22),
                  onPressed: _openNavigation,
                ),
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

  Widget _homeSessionRow(AppState state, SessionRef ref) =>
      _sessionRow(state, ref, favorite: true);

  Widget _sessionRow(AppState state, SessionRef ref, {bool favorite = false}) =>
      projectSessionRow(
        context,
        state,
        ref,
        key: ValueKey(
          '${favorite ? 'home' : 'session'}-${ref.desktopId}-${ref.session.id}',
        ),
        compact: true,
        favorite: favorite,
        selected: _conversation?.desktop == ref.desktopId &&
            _conversation?.session == ref.session.id,
        onTap: () => _showSession(ref),
      );

  Widget _projectRow(AppState state, ConversationProject item) {
    final ref = item.ref;
    final sessions = item.sessions;
    final key = (ref.desktopId, ref.project.id);
    final collapsed = _collapsed.contains(key);
    final all = _showAll.contains(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProjectActionRow(
          key: ValueKey('project-${ref.desktopId}-${ref.project.id}'),
          state: state,
          project: ref,
          child: ListRow(
            leading: ProjectIconView(state: state, ref: ref),
            title: ref.project.name,
            subtitle: state.tr('${sessions.length} 段对话',
                '${sessions.length} conversations'),
            flags: statusFlags(context, state, sessions),
            aside: ref.project.pinned == true
                ? const LucideIcon('pin', size: 16)
                : null,
            status: IconButton(
              key: ValueKey('project-fold-${ref.desktopId}-${ref.project.id}'),
              tooltip: collapsed
                  ? state.tr('展开项目', 'Expand project')
                  : state.tr('收起项目', 'Collapse project'),
              icon: LucideIcon(collapsed ? 'chevron-right' : 'chevron-down', size: 18),
              onPressed: () => setState(() {
                if (collapsed) {
                  _collapsed.remove(key);
                } else {
                  _collapsed.add(key);
                }
              }),
            ),
            onTap: () => _showNew(ref, false),
          ),
        ),
        if (!collapsed) ...[
          for (final session in all ? sessions : sessions.take(5))
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _sessionRow(state, session),
            ),
          if (sessions.length > 5)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: ValueKey('project-more-${ref.desktopId}-${ref.project.id}'),
                onPressed: () => setState(() {
                  if (all) {
                    _showAll.remove(key);
                  } else {
                    _showAll.add(key);
                  }
                }),
                child: Text(all
                    ? state.tr('收起多余对话', 'Show fewer')
                    : state.tr('展开剩余 ${sessions.length - 5} 条',
                        'Show ${sessions.length - 5} more')),
              ),
            ),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 16, 12),
              child: Text(state.tr('还没有对话，直接开始新任务。',
                  'No conversations yet. Start a new task.'),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ],
    );
  }

  List<Widget> _navigationRows(
    List<ConversationProject> projects,
    List<BotRef> bots,
    List<SessionRef> home,
  ) {
    final state = widget.state;
    final favorites = _filters.copyWith(query: '').sessions(
      home, state.desktopName,
    );
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
      if (favorites.isNotEmpty) ...[
        SectionLabel(state.tr('常用对话', 'Favorites')),
        for (final ref in favorites) _homeSessionRow(state, ref),
      ],
      for (final item in projects) _projectRow(state, item),
      if (orderedBots.isNotEmpty) ...[
        const SectionLabel('Bot'),
        for (final ref in orderedBots)
          _BotChatRow(
            key: ValueKey('bot-${ref.desktopId}-${ref.bot.id}'),
            state: state,
            ref: ref,
          ),
      ],
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

class _BotChatRow extends StatelessWidget {
  const _BotChatRow({super.key, required this.state, required this.ref});
  final AppState state;
  final BotRef ref;
  @override
  Widget build(BuildContext context) => BotPressRow(
    state: state,
    ref: ref,
    child: ListRow(
      leading: Badge(
        isLabelVisible: ref.bot.unread > 0,
        label: Text('${ref.bot.unread}'),
        offset: const Offset(6, -6),
        child: BotAvatar(state: state, ref: ref),
      ),
      title: ref.bot.name,
      subtitle: ref.bot.last,
      time: switch (ref.bot.updatedAt) {
        final at? => _sessionTime(state, at),
        null => null,
      },
      status: state.botPinned(ref) ? const LucideIcon('pin', size: 16) : null,
      onTap: () => openPage<void>(
        context,
        ChatPage(
          state: state,
          desktopId: ref.desktopId,
          sessionId: ref.bot.session ?? 'bot:${ref.bot.id}',
          title: ref.bot.name,
          botId: ref.bot.id,
        ),
      ),
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

/// A conversation in a project's list: in the project's page, the home list
/// filtered to the project, and under a project unfolded there.
Widget projectSessionRow(
  BuildContext context,
  AppState state,
  SessionRef ref, {
  Key? key,
  VoidCallback? onTap,
  bool compact = false,
  bool favorite = false,
  bool selected = false,
}) {
  // 放到首页的：提醒在首页那行，这里只灰着标出来。
  final home = state.onHome(ref);
  final flags = statusFlags(context, state, [ref], counted: false);
  return SessionPressRow(
    key: key ?? ValueKey('session-${ref.desktopId}-${ref.session.id}'),
    state: state,
    session: ref,
    child: ListRow(
      leading: compact
          ? const Center(child: LucideIcon('message-circle', size: 20))
          : home
          ? homeWaitingDot(context, state, ref, LetterAvatar(ref.session.title))
          : waitingAvatar(state, LetterAvatar(ref.session.title), [ref]),
      title: ref.session.title,
      note: !compact && home ? state.tr('常用', 'Favorite') : null,
      aside: modelTag(context, state, ref),
      flags: home && !compact
          ? [
              for (final (label, _) in flags)
                (label, Theme.of(context).hintColor),
            ]
          : flags,
      subtitle: compact
          ? favorite
                ? state.projects
                        .where((p) => p.desktopId == ref.desktopId &&
                            p.project.id == ref.session.project)
                        .firstOrNull?.project.name ?? ref.session.project
                : null
          : lastLine(state, ref),
      time: _sessionTime(state, ref.session.updatedAt),
      status: ref.session.pinned
          ? const LucideIcon('pin', size: 16)
          : selected
          ? const LucideIcon('check', size: 16)
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

/// [avatar] with a grey dot when [ref] waits on the user: the red count is
/// on the conversation's own row on the home list, this only points there.
/// In a project's list the row carries the 首页 tag, so a red count here
/// would read as work to do in the project, and two counts would disagree.
Widget homeWaitingDot(
  BuildContext context,
  AppState state,
  SessionRef ref,
  Widget avatar,
) {
  final counts = state.countByStatus([ref]);
  final waiting = counts.needsInput + counts.done;
  return Badge(
    key: ValueKey('home-waiting-dot-${ref.desktopId}-${ref.session.id}'),
    isLabelVisible: waiting > 0,
    smallSize: 7,
    backgroundColor: Theme.of(context).hintColor,
    child: avatar,
  );
}

/// The conversations [project] stands for on the home list: those put on
/// the home list have rows of their own, and are counted there instead.
Iterable<SessionRef> notOnHome(AppState state, Iterable<SessionRef> project) =>
    project.where((ref) => !state.onHome(ref));

String _sessionTime(AppState state, DateTime date, [DateTime? now]) {
  now ??= DateTime.now();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(date.year, date.month, date.day)).inDays;
  if (days <= 0) {
    return formatClock(date);
  }
  if (days == 1) return state.tr('昨天', 'Yesterday');
  if (days < 7) {
    const zh = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return state.tr(zh[date.weekday - 1], en[date.weekday - 1]);
  }
  return formatDay(state, date, now: now);
}

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
