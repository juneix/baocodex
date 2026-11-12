// YCode — GPL-3.0-only.
import 'dart:async';
import 'dart:math' as math;

import 'package:bao_link/bao_link.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:image_picker/image_picker.dart';

import '../../chat/chat_models.dart';
import '../../chat/chat_clipboard.dart';
import '../../chat/chat_output.dart';
import '../../chat/step_folds.dart';
import '../../chat/widgets/edits_fold_line.dart';
import '../../chat/widgets/fold_line.dart';
import '../../chat/widgets/notice_row.dart';
import '../../chat/message_view.dart';
import '../../chat/widgets/pixel_loader.dart';
import '../../link/chat_codec.dart';
import '../../models/user_facing_error.dart';
import '../../platform/permission_menu.dart';
import '../../link/phone_link.dart' show DesktopLinkStatus;
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../state/conversation_binding.dart';
import '../../state/conversation_input.dart';
import '../../state/local_message_queue.dart';
import '../files/files_tab.dart';
import '../bots/bots_tab.dart';
import '../widgets/image_gallery.dart';
import '../widgets/bottom_sheet_panel.dart';
import '../widgets/lucide_icon.dart';
import '../widgets/dropdown_panel.dart';
import '../widgets/fold_row.dart';
import '../widgets/mobile_widgets.dart';
import '../widgets/model_icon.dart';
import 'changes_page.dart';
import 'goal_page.dart';
import 'interaction_panel.dart';
import 'bot_working_line.dart';
import 'emoji_panel.dart';
import 'model_settings_sheet.dart';
import 'chat_empty_state.dart';
import 'chat_composer_action.dart';
import 'task_stop_button.dart';
import 'composer_banners.dart';
import 'session_sync_notice.dart';
import 'slash_commands.dart';
import 'chat_activity_card.dart';
import 'context_usage.dart';
import 'rewind_files.dart';
import 'running_agents.dart';
import '../devices/device_menu.dart' show linkStatusLabel;
import '../conversations/chats_tab.dart' show newConversation;
import '../conversations/delete_conversation.dart';
import '../conversations/open_conversation.dart';
import 'task_page.dart';
import 'subagent_page.dart';
import '../user_message.dart';
import '../widgets/formats.dart';

part 'chat_page_choices.dart';
part 'chat_page_composer.dart';
part 'chat_page_history.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.state,
    required this.desktopId,
    this.sessionId,
    required this.title,
    this.projectId,
    this.botId,
    this.projectUnavailable = false,
    this.active = true,
    this.onSwitchProject,
    this.onOpenNavigation,
    this.onNewConversation,
    this.onCloseConversation,
    this.onSessionCreated,
  });
  final bool projectUnavailable, active;
  final VoidCallback? onOpenNavigation,
      onNewConversation,
      onCloseConversation;
  final ValueChanged<String>? onSessionCreated;

  /// A new conversation, not begun yet, may go to another project: this
  /// picks it and opens it in this page's place.
  final Future<void> Function(BuildContext context)? onSwitchProject;
  final AppState state;
  final String desktopId, title;
  final String? sessionId, projectId, botId;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final TextEditingController _composer;
  final _scroll = ScrollController();
  final _historyListKey = GlobalKey();
  var _historyRowKeys = <(String, int), GlobalKey>{};
  List<ChatRow> _rows = const [];
  int _jumpTicket = 0;
  final _composerFocus = FocusNode();
  final _scaffold = GlobalKey<ScaffoldState>();
  final _addRegion = Object();
  bool _addOpen = false, _actionsOpen = false;
  double _navigationDrag = 0;
  // 打开的是表情面板，不是加号面板；只有 Bot 有。
  bool _emojiPanel = false;
  bool get _pinned => widget.state.sessions.any(
    (ref) =>
        ref.desktopId == widget.desktopId &&
        ref.session.id == _sessionId &&
        ref.session.pinned,
  );
  final _images = <DraftImage>[];
  final _mentions = <String>{};
  Timer? _draftTimer;
  bool _sending = false, _commandBusy = false, _picking = false;

  /// The conversation has been asked for once: an empty one is empty, not
  /// still on its way.
  bool _opened = false;
  int? _editIndex;
  String? _beforeEdit;
  MessageEditAnchor? _editAnchor;
  bool _draftDirty = false,
      _imagesMissing = false,
      _beforeEditImagesMissing = false;
  final _beforeEditImages = <DraftImage>[];
  final _beforeEditMentions = <String>{};
  String? _error;
  bool _follow = true;

  /// 往回看时运行中的回合：它和之后的回合先不收起，否则内容一短位置就被顶到底部。
  int? _keepOpenFrom;

  /// 这一条及之后往下长，之前的往上长：往前加载时现有内容一动不动。
  int _centerItem = 0;
  String? _centerSession;

  /// 打开时列表已经到了底部才显示，看不到它从顶上滚下来。
  bool _placed = false, _placing = false;
  bool _userScrolling = false;
  bool _loadingEarlier = false;
  Future<void>? _earlierLoad;
  Object? _preloadedFrom;
  String? _earlierError;
  final _away = ValueNotifier<bool>(false);

  /// Bumped as the user starts to scroll: the tray over the composer folds.
  final _trayFold = ValueNotifier<int>(0);
  late final ConversationBinding _binding;
  late final _entryBuffer = SessionBuffer(widget.desktopId, _draftSession);
  String? _createdSession;
  Future<String?>? _creatingSession;
  bool _sawBot = false;
  int _lastRevision = -1;

  /// Which folds (a run of steps, a turn's work) stand open.
  final _foldsOpen = <(StepFoldKind, int), bool>{};

  /// 换上游的模型画在哪：行号（从 1 起）前面几条，和最后一行后面几条。
  final _marksBefore = <int, List<String>>{};
  final _marksAfter = <String>[];

  /// 电脑上这个项目的 `.claude/commands` 和能用的技能，打 `/` 时问；
  /// null 是还没拿到，过了 [_desktopCommandsDue] 再打 `/` 时重问。
  List<SlashCommand>? _projectCommands, _skills;
  DateTime _desktopCommandsDue = DateTime(0);

  /// Plans the desktop answered `notFound` to Start for: not pending any
  /// more, whatever the history says (see [pendingPlans]).
  final _lostPlans = <String>{};
  String get _draftSession => widget.botId != null
      ? 'bot:${widget.botId}'
      : _createdSession ??
            widget.sessionId ??
            AppState.newConversationDraftKey(widget.projectId ?? '');
  bool get _editValid => _editAnchor?.matches(_buffer) ?? true;
  // 同步途中手机和电脑的序号可能对不上，等它完成再发。
  bool get _editReady => _editValid && !(_editIndex != null && _buffer.loading);
  InputDraft get _input => InputDraft(
    text: _composer.text,
    images: List.of(_images),
    mentions: Set.of(_mentions),
    imagesMissing: _imagesMissing,
  );
  String get _sessionId => _binding.sessionId ?? _draftSession;
  bool get _hasSession => _binding.sessionId != null;
  SessionBuffer get _buffer => widget.botId == null && !_hasSession
      ? _entryBuffer
      : widget.state.buffer(widget.desktopId, _sessionId);
  bool get _online =>
      _binding.available && widget.state.isOnline(widget.desktopId);
  ProjectRef? get _project => widget.state.projects
      .where(
        (ref) =>
            ref.desktopId == widget.desktopId &&
            ref.project.id == widget.projectId,
      )
      .firstOrNull;
  String tr(String zh, String en) => widget.state.tr(zh, en);

  @override
  void initState() {
    super.initState();
    _opened = widget.botId == null && widget.sessionId == null;
    _binding = ConversationBinding(
      // 首帧就用真实会话，已有的消息不必先闪一下加载中。
      sessionId: widget.botId == null
          ? (widget.sessionId?.startsWith('bot:') == true
                ? null
                : widget.sessionId)
          : widget.state.bots
                .where(
                  (ref) =>
                      ref.desktopId == widget.desktopId &&
                      ref.bot.id == widget.botId,
                )
                .firstOrNull
                ?.bot
                .session,
      retain: (session) => widget.state.openSession(widget.desktopId, session),
      release: (session) =>
          widget.state.closeSession(widget.desktopId, session),
      refreshSession: (session) =>
          widget.state.refreshSession(widget.desktopId, session),
      verifyTarget: widget.botId == null
          ? null
          : () async {
              if (!widget.state.ready) {
                return ConversationTarget(sessionId: _binding.sessionId);
              }
              final snapshot = await widget.state.refreshDesktopState(
                widget.desktopId,
              );
              final bot = snapshot.bots
                  .where((bot) => bot.id == widget.botId)
                  .firstOrNull;
              return ConversationTarget(
                sessionId: bot?.session,
                available: bot != null,
              );
            },
    );
    final draft = widget.state.inputDraft(
      widget.desktopId,
      _draftSession,
      legacySessionId: widget.sessionId,
    );
    _images.addAll(draft.images);
    _mentions.addAll(draft.mentions);
    _imagesMissing = draft.imagesMissing;
    _composer = TextEditingController(
      text: draft.text.isNotEmpty
          ? draft.text
          : widget.state.draft(widget.desktopId, _draftSession),
    );
    _composer.addListener(_draftChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _binding.addListener(_bindingChanged);
      widget.state.addListener(_workspaceChanged);
      _workspaceChanged();
      unawaited(
        _binding.settled.whenComplete(() {
          if (mounted) setState(() => _opened = true);
        }),
      );
    });
  }

  void _bindingChanged() {
    if (mounted) setState(() {});
  }

  void _workspaceChanged() {
    if (!mounted) return;
    final botId = widget.botId;
    String? session = widget.sessionId?.startsWith('bot:') == true
        ? null
        : _createdSession ?? widget.sessionId;
    var available = true;
    if (botId != null) {
      final bot = widget.state.bots
          .where(
            (ref) => ref.desktopId == widget.desktopId && ref.bot.id == botId,
          )
          .firstOrNull;
      if (bot != null) {
        _sawBot = true;
        session = bot.bot.session;
      } else {
        available =
            !_sawBot &&
            !(widget.state.ready &&
                widget.state.snapshots.containsKey(widget.desktopId));
        session = available ? (_binding.sessionId ?? session) : null;
      }
    }
    _binding.update(
      sessionId: session,
      online: widget.state.isOnline(widget.desktopId),
      available: available,
    );
    // A turn that ended lets the messages queued on the phone go out.
    if (_hasSession) {
      widget.state.localQueue.drain(widget.desktopId, _sessionId);
    }
  }

  Future<void> _open() => _binding.refresh();

  Future<String?> _ensureSession() async {
    if (_hasSession) return _binding.sessionId;
    final pending = _creatingSession;
    if (pending != null) return pending;
    final creation = _createSession();
    setState(() {
      _creatingSession = creation;
    });
    try {
      return await creation;
    } finally {
      if (mounted && identical(_creatingSession, creation)) {
        setState(() => _creatingSession = null);
      }
    }
  }

  Future<String?> _createSession() async {
    final project = _project;
    if (!_online || project == null) {
      throw UserFacingError(
        tr(
          '连接电脑并选择可用项目后才能开始。',
          'Connect a desktop and select an available project first.',
        ),
      );
    }
    unawaited(widget.state.rememberProject(project).catchError((Object error) {
      if (mounted) setState(() => _error = userMessage(widget.state, error));
    }));
    final result = objectMap(
      await widget.state.request(widget.desktopId, LinkMethods.draft, {
        'project': project.project.id,
      }),
    );
    final actual = result['session'];
    if (actual is! String || actual.isEmpty) {
      throw const FormatException('The desktop did not return a session');
    }
    if (!mounted) return null;
    final source = _draftSession;
    final draft = _input;
    _draftTimer?.cancel();
    _createdSession = actual;
    _binding.update(
      sessionId: actual,
      online: widget.state.isOnline(widget.desktopId),
      verified: true,
    );
    // 两个内存键先同步迁移，慢写不能阻塞发送或清掉后来输入的新草稿。
    unawaited(
      Future.wait([
        widget.state.saveInputDraft(widget.desktopId, actual, draft),
        if (source != actual)
          widget.state.saveInputDraft(
            widget.desktopId,
            source,
            const InputDraft(),
          ),
      ]).then<void>((_) {}).catchError((Object error) {
        if (mounted) {
          setState(() => _error = userMessage(widget.state, error));
        }
      }),
    );
    widget.onSessionCreated?.call(actual);
    return actual;
  }

  void _closeConversation() {
    final close = widget.onCloseConversation;
    if (close != null) {
      close();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _draftChanged() {
    if (mounted) setState(() {});
    if (_editIndex != null) return;
    _draftDirty = true;
    final project = _project;
    if (!_hasSession && widget.botId == null && project != null) {
      unawaited(widget.state.rememberProject(project).catchError((Object error) {
        if (mounted) setState(() => _error = userMessage(widget.state, error));
      }));
    }
    _draftTimer?.cancel();
    _draftTimer = Timer(
      const Duration(milliseconds: 350),
      () => _saveDraft(_composer.text),
    );
  }

  void _saveDraft(String text) {
    // 立即更新内存草稿；安全存储写入由 AppState 串行化，慢写不阻断跨页恢复。
    _draftTimer?.cancel();
    _draftDirty = false;
    final state = widget.state,
        desktop = widget.desktopId,
        session = _draftSession;
    final draft = InputDraft(
      text: text,
      images: List.of(_images),
      mentions: Set.of(_mentions),
      imagesMissing: _imagesMissing,
    );
    unawaited(
      state.saveInputDraft(desktop, session, draft).catchError((Object error) {
        if (mounted) setState(() => _error = userMessage(state, error));
      }),
    );
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _reserveTimer?.cancel();
    if (_editIndex == null && _draftDirty) _saveDraft(_composer.text);
    _composer.removeListener(_draftChanged);
    _composer.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    _away.dispose();
    _trayFold.dispose();
    widget.state.removeListener(_workspaceChanged);
    _binding.removeListener(_bindingChanged);
    _binding.dispose();
    super.dispose();
  }

  Future<void> _command(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (_commandBusy || !_hasSession) return;
    setState(() {
      _commandBusy = true;
      _error = null;
    });
    try {
      await widget.state.request(widget.desktopId, method, {
        'session': _sessionId,
        ...params,
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = userMessage(widget.state, error));
      }
    } finally {
      if (mounted) setState(() => _commandBusy = false);
    }
  }

  /// Starts [raw], the plan [pendingPlans] found pending. The desktop has
  /// the last word: when it is not waiting on that plan after all
  /// (`notFound`), the plan reads expired and the button goes, and the
  /// composer offers the words to go on with instead of a dead end.
  Future<void> _startPlan(Object? raw) async {
    if (_commandBusy || !_hasSession) return;
    final plan = ChatCodec.decode(raw);
    setState(() {
      _commandBusy = true;
      _error = null;
    });
    try {
      await widget.state.request(widget.desktopId, LinkMethods.startPlan, {
        'session': _sessionId,
      });
    } catch (error) {
      if (!mounted) return;
      final gone =
          error is LinkRemoteException &&
          error.code == LinkErrors.notFound &&
          plan is PlanItem;
      setState(() {
        if (!gone) {
          _error = userMessage(widget.state, error);
          return;
        }
        _lostPlans.add(planKey(plan));
        if (_composer.text.trim().isEmpty) {
          _composer.text = tr('按计划开始执行', 'Go ahead with the plan');
        }
        _error = tr(
          '电脑上这个计划已经不在等你确认了。可以直接发消息让它按计划继续，输入框里已经填好。',
          'The desktop is no longer waiting on this plan. Send a message to go on with it; one is ready in the box.',
        );
      });
    } finally {
      if (mounted) setState(() => _commandBusy = false);
    }
  }

  /// 左滑和右上角「更多」都打开同一个右侧会话抽屉。
  void _openSessionPanel() {
    _composerFocus.unfocus();
    _closeAdd();
    _scaffold.currentState?.openEndDrawer();
  }

  void _requireOnline() {
    if (!_online) {
      throw UserFacingError(
        tr('电脑已离线，操作未执行。',
            'The desktop is offline. No action was performed.'),
      );
    }
  }

  Future<void> _sessionMenu(String action) async {
    final session = _sessionId;
    if (action == 'new') {
      final start = widget.onNewConversation;
      if (start != null) {
        start();
      } else if (_project case final project?) {
        await newConversation(context, widget.state, project: project);
      }
      return;
    }
    if (action == 'changes') {
      await openPage<void>(
        context,
        ChangesPage(
          state: widget.state,
          desktopId: widget.desktopId,
          sessionId: session,
          projectId: widget.projectId,
        ),
      );
      return;
    }
    if (action == 'tasks') {
      await openPage<void>(
        context,
        TasksPage(
          state: widget.state,
          desktopId: widget.desktopId,
          sessionId: session,
        ),
      );
      return;
    }
    _requireOnline();
    switch (action) {
      case 'files':
        final ref = widget.state.projects
            .where(
              (r) =>
                  r.desktopId == widget.desktopId &&
                  r.project.id == widget.projectId,
            )
            .firstOrNull;
        if (ref == null || !mounted) return;
        await openPage<void>(
          context,
          FilesPage(state: widget.state, project: ref),
        );
      case 'pin':
        await widget.state.request(widget.desktopId, LinkMethods.pin, {
          'session': session,
          'pinned': !_pinned,
        });
      case 'rename':
        if (!mounted) return;
        final controller = TextEditingController(text: widget.title);
        final title = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr('重命名', 'Rename')),
            content: TextField(controller: controller, autofocus: true),
            actions: dialogButtons([
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: Text(tr('保存', 'Save')),
              ),
            ]),
          ),
        );
        if (title == null || title.isEmpty) return;
        _requireOnline();
        await widget.state.request(widget.desktopId, LinkMethods.rename, {
          'session': session,
          'title': title,
        });
      case 'delete':
        if (widget.botId != null) return;
        final deleted = await deleteConversation(
          context,
          widget.state,
          desktopId: widget.desktopId,
          sessionId: session,
          title: widget.title,
        );
        if (deleted && mounted) _closeConversation();
      case 'archive':
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr('归档', 'Archive')),
            content: Text(tr('归档后对话从列表收起。', 'The chat moves out of the list.')),
            actions: dialogButtons([
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr('归档', 'Archive')),
              ),
            ]),
          ),
        );
        if (confirmed != true) return;
        _requireOnline();
        await widget.state.request(widget.desktopId, LinkMethods.archive, {
          'session': session,
        });
        if (!mounted) return;
        _closeConversation();
    }
  }

  /// 右侧会话抽屉：上半是快捷入口，下半是会话操作。点一行先关抽屉，
  /// 再交给既有的 [_sessionMenu]，业务逻辑不在这里重写。
  Widget _sessionDrawer(BuildContext context, SessionBuffer buffer) {
    final colors = Theme.of(context).colorScheme;
    final running = buffer.tasks.any((task) => task.status == 'running');
    final canNew = _project != null || widget.onNewConversation != null;
    void run(String action) {
      // 用 Scaffold 的 API 关抽屉；Navigator.pop 会退掉整页。错误提示
      // 挂在页面自己的 context 上，抽屉关掉后仍然有效。
      _scaffold.currentState?.closeEndDrawer();
      runUi(this.context, () => _sessionMenu(action));
    }

    Widget row(
      String key,
      String label,
      String icon, {
      bool enabled = true,
      bool destructive = false,
    }) => ListTile(
      key: ValueKey('session-menu-$key'),
      enabled: enabled,
      leading: LucideIcon(
        icon,
        size: 22,
        color: destructive && enabled ? colors.error : null,
      ),
      title: Text(
        label,
        style: destructive && enabled ? TextStyle(color: colors.error) : null,
      ),
      onTap: enabled ? () => run(key) : null,
    );

    return Drawer(
      key: const ValueKey('session-drawer'),
      width: MediaQuery.sizeOf(context).width * .8,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.state.desktopName(widget.desktopId)} · '
                    '${linkStatusLabel(widget.state, widget.state.linkStatus(widget.desktopId))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MobileTheme.hintStyleOf(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  SectionLabel(tr('快捷入口', 'Shortcuts')),
                  if (widget.projectId != null)
                    row(
                      'files',
                      tr('浏览文件', 'Browse files'),
                      'folder',
                      enabled: _online && _project != null,
                    ),
                  row('changes', tr('全部改动', 'All changes'), 'file-diff'),
                  row(
                    'tasks',
                    tr('后台任务', 'Background tasks'),
                    'list-todo',
                  ),
                  SectionLabel(tr('会话', 'Conversation')),
                  if (canNew)
                    row(
                      'new',
                      tr('新对话', 'New conversation'),
                      'square-pen',
                      enabled: !_sending,
                    ),
                  // 置顶、重命名、归档、删除都针对真实会话；还没开始的
                  // 新对话没有会话可改。
                  if (_hasSession) ...[
                    row(
                      'pin',
                      _pinned ? tr('取消置顶', 'Unpin') : tr('置顶', 'Pin'),
                      'pin',
                      enabled: _online,
                    ),
                    row(
                      'rename',
                      tr('重命名', 'Rename'),
                      'pencil',
                      enabled: _online,
                    ),
                    row(
                      'archive',
                      tr('归档', 'Archive'),
                      'archive',
                      enabled: _online,
                    ),
                    row(
                      'delete',
                      tr('删除', 'Delete'),
                      'trash-2',
                      enabled: _online,
                      destructive: true,
                    ),
                  ],
                  if (!_online)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text(
                        tr(
                          '电脑离线，写操作暂不可用',
                          'Computer offline; write actions are unavailable',
                        ),
                        style: MobileTheme.hintStyleOf(context),
                      ),
                    ),
                ],
              ),
            ),
            if (running)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  tr('有后台任务在运行', 'Background tasks are running'),
                  style: MobileTheme.hintStyleOf(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    if (_sending ||
        !_online ||
        (_composer.text.trim().isEmpty && _images.isEmpty)) {
      return;
    }
    if (_imagesMissing) {
      setState(
        () => _error = tr(
          '部分图片未恢复，请重新添加或明确忽略丢失附件。',
          'Some images could not be restored. Reattach them or explicitly dismiss the missing attachments.',
        ),
      );
      return;
    }
    // The agent is at work (or earlier queued messages still wait): this one
    // waits on the phone with them, so order holds and nothing interrupts.
    if (_editIndex == null && _hasSession && _queueing) {
      _queueDraft();
      return;
    }
    // The notice above says so while editing; it is asked once, as it is sent,
    // with what becomes of the files the agent changed after the message.
    int? planIndex;
    var revertFiles = false;
    if (_editIndex != null) {
      planIndex = _editAnchor?.locate(_buffer);
      var plan = RewindPlan.none;
      if (planIndex != null && !_buffer.loading) {
        setState(() {
          _sending = true;
          _error = null;
        });
        try {
          plan = await loadRewindPlan(
            widget.state,
            widget.desktopId,
            session: _sessionId,
            index: planIndex,
          );
        } catch (error) {
          if (mounted) {
            setState(() => _error = userMessage(widget.state, error));
          }
          return;
        } finally {
          if (mounted) setState(() => _sending = false);
        }
        if (!mounted) return;
      }
      final answer = await askResend(
        context,
        widget.state,
        live: _buffer.live,
        plan: plan,
      );
      if (answer == null) return;
      revertFiles = answer;
    }
    if (!mounted || _sending) return;
    final editIndex = _editAnchor?.locate(_buffer);
    // What was asked of the files is for the message as it was then.
    final moved = revertFiles && editIndex != planIndex;
    if (_editIndex != null && (editIndex == null || moved || _buffer.loading)) {
      setState(
        () => _error = editIndex == null || moved
            ? tr(
                '编辑的消息已变化，请取消后重新选择。',
                'The message changed. Cancel and select it again.',
              )
            : tr(
                '正在同步对话，请稍后再发送。',
                'Syncing the conversation. Send again in a moment.',
              ),
      );
      return;
    }
    final submitted = _input;
    var operationGeneration = _binding.generation;
    final text = _composer.text;
    final images = [for (final image in _images) image.wire];
    final mentions = _mentions
        .where((path) => text.contains('@$path'))
        .toList();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (!_hasSession && widget.botId == null) {
        final created = await _ensureSession();
        if (!mounted || created == null) return;
        if (!_online) {
          throw UserFacingError(
            tr(
              '电脑已断开，输入已保留。',
              'The desktop disconnected. Your input is kept.',
            ),
          );
        }
        operationGeneration = _binding.generation;
      }
      if (editIndex != null) {
        await widget.state.request(widget.desktopId, LinkMethods.edit, {
          'session': _sessionId,
          'index': editIndex,
          'text': text,
          'images': images,
          'mentions': mentions,
          if (revertFiles) 'revertFiles': true,
        });
        if (!mounted) return;
        if (_binding.generation != operationGeneration) {
          throw StateError(
            tr(
              '编辑结果未确认，当前会话已变化',
              'Edit result unconfirmed; conversation changed',
            ),
          );
        }
      } else {
        final generation = operationGeneration;
        final actual = await widget.state.sendMessage(
          widget.desktopId,
          session: _hasSession ? _sessionId : null,
          project: widget.projectId,
          bot: widget.botId,
          text: text,
          images: images,
          mentions: mentions,
        );
        if (!mounted) return;
        if (actual == null || !_binding.acceptSent(actual, generation)) {
          throw StateError(tr('电脑返回的会话未确认', 'Conversation not confirmed'));
        }
      }
      if (!mounted) return;
      // Preserve a newer draft typed while the request was in flight.
      final wasEditing = _editIndex != null;
      final stillSentText = _composer.text == text;
      final remaining = _input.afterSending(submitted);
      _images
        ..clear()
        ..addAll(wasEditing ? _beforeEditImages : remaining.images);
      _mentions
        ..clear()
        ..addAll(wasEditing ? _beforeEditMentions : remaining.mentions);
      _imagesMissing = wasEditing
          ? _beforeEditImagesMissing
          : remaining.imagesMissing;
      if (stillSentText) {
        _composer.text = wasEditing ? (_beforeEdit ?? '') : remaining.text;
      }
      _editIndex = null;
      _editAnchor = null;
      _beforeEdit = null;
      _beforeEditImages.clear();
      _beforeEditMentions.clear();
      _saveDraft(_composer.text);
      _forceBottom();
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = error is UserFacingError
              ? userMessage(widget.state, error)
              : error is LinkClosedException || error is TimeoutException
              ? tr(
                  '连接中断，不确定电脑是否收到。内容已保留，请看一下对话再决定是否重发。',
                  'The connection dropped; the desktop may not have received it. Content is kept; check the conversation before sending again.',
                )
              : tr(
                  '发送未确认；内容已保留，请先检查会话，避免重复发送。',
                  'Send was not confirmed. Content is kept; check the conversation before sending again.',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  double? _viewport;

  Future<void> _edit(int index, UserMessageItem item) async {
    if (_sending || index < 0 || index >= _buffer.items.length) return;
    final anchor = MessageEditAnchor.capture(_buffer, index);
    if (!anchor.matches(_buffer)) {
      setState(
        () => _error = tr(
          '编辑的消息已变化，请取消后重新选择。',
          'The message changed. Cancel and select it again.',
        ),
      );
      return;
    }
    _draftTimer?.cancel();
    if (_editIndex == null) {
      _beforeEdit = _composer.text;
      _beforeEditImagesMissing = _imagesMissing;
      _beforeEditImages
        ..clear()
        ..addAll(_images);
      _beforeEditMentions
        ..clear()
        ..addAll(_mentions);
      _saveDraft(_composer.text);
    }
    if (index >= _buffer.items.length) return;
    setState(() {
      _editIndex = index;
      _editAnchor = anchor;
      _imagesMissing = false;
      _images.clear();
      _mentions.clear();
      for (final image in item.images) {
        _images.add(
          DraftImage(image.name ?? 'image', image.mediaType, image.bytes),
        );
      }
      _composer.text = messageBody(item.text, item.images);
    });
  }

  void _cancelEdit() {
    setState(() {
      // Set controller while still in editing mode so it cannot overwrite the saved draft.
      _composer.text = _beforeEdit ?? '';
      _images
        ..clear()
        ..addAll(_beforeEditImages);
      _mentions
        ..clear()
        ..addAll(_beforeEditMentions);
      _imagesMissing = _beforeEditImagesMissing;
      _editIndex = null;
      _editAnchor = null;
      _beforeEdit = null;
      _beforeEditImages.clear();
      _beforeEditMentions.clear();
    });
    _saveDraft(_composer.text);
  }

  bool _pasting = false;

  @override
  Widget build(BuildContext context) => PopScope(
    // 隐藏的标签页不拦截返回；附件面板先关闭，再回到新对话入口。
    canPop:
        !widget.active || (!_addOpen && widget.onCloseConversation == null),
    onPopInvokedWithResult: (didPop, _) {
      if (didPop || !widget.active) return;
      if (_addOpen) {
        _closeAdd();
      } else {
        widget.onCloseConversation?.call();
      }
    },
    child: AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final buffer = _buffer;
        if (_lastRevision != buffer.revision) {
          if (_follow && !buffer.loadingEarlier) _bottom();
          _lastRevision = buffer.revision;
        }
        final ready =
            _online &&
            !_sending &&
            !_picking &&
            (_hasSession || widget.botId != null || _project != null);
        final error =
            _error ??
            (_binding.error == buffer.error ? null : _binding.error) ??
            (buffer.items.isEmpty ? buffer.error : null);
        // Display rows: consecutive quiet info tools collapse into one
        // aggregated line, the way the original app renders a stream.
        if (!_follow) _holdRunningTurn();
        // 哪条计划电脑真在等：按钮和计划卡片都看这一处。
        // 点了立即插入、电脑还没接上的消息：电脑那边排着，对话里先替它占一条。
        final items = [
          ...buffer.items,
          if (_hasSession)
            for (final message in widget.state.localQueue.inserting(
              widget.desktopId,
              _sessionId,
            ))
              ChatCodec.encode(
                UserMessageItem(
                  text: message.text,
                  queued: true,
                  images: [
                    for (final image in message.images)
                      ImageAttachment(
                        bytes: image.bytes,
                        mediaType: image.type,
                        name: image.name,
                      ),
                  ],
                ),
              ),
        ];
        final plans = pendingPlans(items, lost: _lostPlans);
        final rows = widget.botId != null
            ? botRows(items)
            : foldRows(
                    plans.items,
                    live: buffer.live == true,
                    keepOpenFrom: _keepOpenFrom,
                    isOpen: (fold) => _foldsOpen[fold.key] ?? false,
                  )
                  .where((row) => _online || row.shown is! LiveStatusItem)
                  .toList();
        _rows = rows;
        final bot = widget.state.bots
            .where(
              (ref) =>
                  ref.desktopId == widget.desktopId &&
                  ref.bot.id == widget.botId,
            )
            .firstOrNull;
        return Scaffold(
          key: _scaffold,
          appBar: _appBar(context, buffer, bot),
          endDrawer: widget.botId == null
              ? _sessionDrawer(context, buffer)
              : null,
          // 手势由正文里的 GestureDetector 统一触发，避免和右侧抽屉的边缘
          // 拖动重复打开。
          endDrawerEnableOpenDragGesture: false,
          // What was running is only last known once disconnected: nothing
          // animates as if it were still at work.
          body: TickerMode(
            enabled: _online,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  if (buffer.items.isNotEmpty)
                    SessionSyncNotice(
                      key: ValueKey(('sync', widget.desktopId, _sessionId)),
                      state: widget.state,
                      online: _online,
                      loading: buffer.loading,
                      error: buffer.error,
                      onRetry: _open,
                      onLayoutChange: _preserveReadingPosition,
                    ),
                  // 和「内容未更新」一样一行小字，不再整块横幅挡住对话。
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                      child: ComposerNotice(
                        icon: 'triangle-alert',
                        title: error,
                        tone: Theme.of(context).colorScheme.error,
                        actionLabel:
                            buffer.error != null || _binding.error != null
                            ? tr('重新加载', 'Reload')
                            : tr('关闭', 'Dismiss'),
                        onAction: () {
                          setState(() => _error = null);
                          if (buffer.error != null || _binding.error != null) {
                            _open();
                          }
                        },
                      ),
                    ),
                  if (widget.projectUnavailable)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _hasSession
                            ? tr(
                                '项目上下文暂不可用；可以读取会话，依赖项目的文件入口不提供。',
                                'Project context is unavailable. Conversation reads remain available; project-dependent file actions are hidden.',
                              )
                            : tr(
                                '所选项目暂不可用，请在侧栏选择项目；输入已保留。',
                                'The selected project is unavailable. Choose one in the sidebar; your input is kept.',
                              ),
                      ),
                    ),
                  if (buffer.goal case final goal?) _goalTile(context, goal),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        _composerFocus.unfocus();
                        _closeAdd();
                      },
                      onHorizontalDragStart: widget.onOpenNavigation == null || widget.botId != null
                          ? null
                          : (_) => _navigationDrag = 0,
                      onHorizontalDragUpdate: widget.onOpenNavigation == null || widget.botId != null
                          ? null
                          : (details) => _navigationDrag += details.delta.dx,
                      onHorizontalDragEnd: widget.onOpenNavigation == null || widget.botId != null
                          ? null
                          : (details) {
                              final velocity = details.primaryVelocity ?? 0;
                              if (_navigationDrag.abs() < 64 && velocity.abs() < 600) return;
                              _composerFocus.unfocus();
                              _closeAdd();
                              final direction = _navigationDrag.abs() >= 64 ? _navigationDrag : velocity;
                              if (direction > 0) {
                                widget.onOpenNavigation?.call();
                              } else {
                                _openSessionPanel();
                              }
                            },
                      child: _historyArea(context, buffer, rows, bot, ready),
                    ),
                  ),
                  if (buffer.interaction case final request?)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * .46,
                      ),
                      child: SingleChildScrollView(
                        child: InteractionPanel(
                          key: ValueKey((
                            widget.desktopId,
                            _sessionId,
                            request['id'],
                          )),
                          state: widget.state,
                          desktopId: widget.desktopId,
                          sessionId: _sessionId,
                          projectId: widget.projectId,
                          request: request,
                          enabled: _online,
                        ),
                      ),
                    ),
                  if (plans.pending case final pending?)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FilledButton.icon(
                        style: MobileSizes.wideButton,
                        onPressed: !_online || buffer.live || _commandBusy
                            ? null
                            : () => _startPlan(buffer.items[pending]),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(tr('开始执行计划', 'Start plan')),
                      ),
                    ),
                  if (_imagesMissing)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                      child: ComposerNotice(
                        icon: 'image',
                        title: tr('草稿里的图片没恢复', 'Draft images were lost'),
                        detail: tr('请重新添加', 'reattach them'),
                        tone: MobileTheme.statusColorsOf(context).warning,
                        actionLabel: tr('忽略', 'Dismiss'),
                        onAction: _sending
                            ? null
                            : () {
                                _imagesMissing = false;
                                _draftChanged();
                              },
                      ),
                    ),
                  _composerView(buffer, ready),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  PreferredSizeWidget _appBar(
    BuildContext context,
    SessionBuffer buffer,
    BotRef? bot,
  ) => AppBar(
    // A hairline under the bar, as messengers draw it.
    shape: Border(
      bottom: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant,
        width: .5,
      ),
    ),
    toolbarHeight:
        (MediaQuery.textScalerOf(context).scale(16) * 1.2 +
                MediaQuery.textScalerOf(context).scale(13) * 1.4 +
                12)
            .clamp(56, double.infinity)
            .toDouble(),
    centerTitle: false,
    titleSpacing: 8,
    // 顶栏两侧与内容区、输入区同一条边线。
    leadingWidth: widget.onOpenNavigation != null ? 52 : null,
    leading: widget.onOpenNavigation != null
        ? Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Center(
              child: IconButton(
                tooltip: tr('项目与对话', 'Projects and conversations'),
                style: _circleButton(context),
                icon: const LucideIcon('menu', size: 20),
                onPressed: () {
                  _composerFocus.unfocus();
                  _closeAdd();
                  widget.onOpenNavigation!();
                },
              ),
            ),
          )
        : widget.botId == null
        ? null
        : IconButton(
            tooltip: tr('返回', 'Back'),
            onPressed: () => Navigator.maybePop(context),
            icon: const LucideIcon('arrow-left', size: 22),
          ),
    title: SessionSyncGate(
      online: _online,
      loading: buffer.loading,
      builder: (context, syncing) => widget.botId != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bot?.bot.status == BotStatus.typing
                      ? tr('对方正在输入…', 'Typing…')
                      : bot?.bot.name ?? widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                _connectionLine(context, syncing: syncing),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                _connectionLine(context, syncing: syncing),
              ],
            ),
    ),
    // 右侧一个胶囊里放「新对话」和「更多」，白底黑图标。
    actions: [
      if (widget.botId != null)
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: IconButton(
              tooltip: tr('资料', 'Profile'),
              style: _circleButton(context),
              icon: const LucideIcon('ellipsis', size: 20),
              onPressed: () => openPage<void>(
                context,
                BotProfilePage(state: widget.state, ref: bot!, fromChat: true),
              ),
            ),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: _capsule(
              context,
              children: [
                if (widget.onNewConversation != null)
                  IconButton(
                    tooltip: tr('新对话', 'New conversation'),
                    style: _capsuleButton(context),
                    icon: const LucideIcon('message-circle-plus', size: 20),
                    onPressed: _sending ? null : widget.onNewConversation,
                  ),
                IconButton(
                  key: const ValueKey('chat-open-session-menu'),
                  tooltip: tr('更多', 'More'),
                  style: _capsuleButton(context),
                  icon: Badge(
                    isLabelVisible: buffer.tasks.any(
                      (task) => task.status == 'running',
                    ),
                    child: const LucideIcon('ellipsis', size: 20),
                  ),
                  onPressed: _openSessionPanel,
                ),
              ],
            ),
          ),
        ),
    ],
  );

  /// 白底圆形按钮：和左侧菜单、侧栏按钮同一尺寸。
  ButtonStyle _circleButton(BuildContext context) =>
      IconButton.styleFrom(
        fixedSize: const Size.square(MobileSizes.iconButton),
        padding: EdgeInsets.zero,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        shape: const CircleBorder(),
      );

  /// 胶囊里的一个动作：不各自带底色，命中区 44（Apple 下限）。
  ButtonStyle _capsuleButton(BuildContext context) =>
      IconButton.styleFrom(
        fixedSize: const Size.square(44),
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        shape: const CircleBorder(),
      );

  /// 白底胶囊：视觉高度与左侧圆形按钮一致（36），
  /// 里面的按钮各有 44 的命中区，超出部分透明、不改变外观。
  Widget _capsule(BuildContext context, {required List<Widget> children}) =>
      Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            top: 4,
            bottom: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: children),
        ],
      );

  Widget _goalTile(BuildContext context, Map<String, Object?> goal) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: FoldRow(
      leading: const LucideIcon('flag', size: 18),
      title: Text(
        '${goal['condition'] ?? ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(goalStateLabel(widget.state, '${goal['state'] ?? ''}')),
      trailing: IconButton(
        tooltip: tr('目标详情', 'Goal details'),
        visualDensity: VisualDensity.compact,
        icon: const LucideIcon('square-arrow-out-up-right', size: 18),
        onPressed: () => openGoalPage(
          context,
          state: widget.state,
          desktopId: widget.desktopId,
          sessionId: _sessionId,
          goal: goal,
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${goal['reason'] ?? ''}'),
              const SizedBox(height: MobileSpace.xs),
              Text(
                '${tr('检查次数', 'Checks')}: ${goal['checks'] ?? 0}  ·  ${goal['tokens'] ?? 0} tokens',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  DesktopLinkStatus get _status => widget.state.linkStatus(widget.desktopId);

  /// Under the title: where the conversation is, and how the desktop is
  /// connected, in words as soon as it is not.
  Widget _connectionLine(
    BuildContext context, {
    bool center = false,
    bool syncing = false,
  }) {
    final status = _status;
    final isSyncing = syncing && status == DesktopLinkStatus.online;
    final scheme = Theme.of(context).colorScheme;
    // 圆点：在线绿、离线灰、要重新配对红；连接中和同步中都是主题色的转圈，
    // 两件事都是「正在忙」，不各用一色。
    final Widget mark = switch (status) {
      DesktopLinkStatus.connecting => ConnectingSpinner(
        size: 10,
        color: scheme.primary,
      ),
      DesktopLinkStatus.online when isSyncing => ConnectingSpinner(
        size: 10,
        color: scheme.primary,
      ),
      DesktopLinkStatus.online => Icon(
        Icons.circle,
        size: 7,
        color: MobileTheme.statusColorsOf(context).success,
      ),
      DesktopLinkStatus.needsPairing => Icon(
        Icons.circle,
        size: 7,
        color: scheme.error,
      ),
      DesktopLinkStatus.offline => Icon(
        Icons.circle,
        size: 7,
        color: scheme.onSurfaceVariant,
      ),
    };
    final label = switch (status) {
      DesktopLinkStatus.online when isSyncing => tr('同步中…', 'Syncing…'),
      DesktopLinkStatus.online =>
        _project?.project.name ?? linkStatusLabel(widget.state, status),
      _ => linkStatusLabel(widget.state, status),
    };
    // Bot 和可打开侧栏的普通对话显示「电脑名 · 状态」；独立路由的普通对话
    // 只写状态，标题下一行保持简短。
    final text = widget.botId != null || widget.onOpenNavigation != null
        ? '${widget.state.desktopName(widget.desktopId)} · $label'
        : label;
    return Semantics(
      label: switch (status) {
        DesktopLinkStatus.online when isSyncing => tr(
          '正在同步最新消息',
          'Syncing latest messages',
        ),
        DesktopLinkStatus.online => tr('已连接电脑', 'Desktop connected'),
        DesktopLinkStatus.connecting => tr('正在连接电脑', 'Connecting to desktop'),
        _ => tr('电脑离线', 'Desktop offline'),
      },
      child: Row(
        mainAxisSize: center ? MainAxisSize.min : MainAxisSize.max,
        children: [
          mark,
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // 只有真要处理的那种（需重新配对）用红字；离线是灰的，
              // 和左边的灰点一致。
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: status == DesktopLinkStatus.needsPairing
                    ? scheme.error
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 这一轮开始的时刻：实时状态带着它，否则看最后一条用户消息。
  DateTime? _turnStart(SessionBuffer buffer) {
    final items = buffer.items;
    final recent = items.sublist(math.max(0, items.length - 8));
    for (final item in decodeItems(recent).reversed) {
      switch (item) {
        case LiveStatusItem(:final startedAt?):
          return startedAt.toLocal();
        case UserMessageItem(:final sentAt?):
          return sentAt.toLocal();
        default:
      }
    }
    return null;
  }

  /// The last keyboard height seen with the composer focused; the add panel
  /// takes its place.
  double? _seenKeyboard;

  /// The room the closed panel keeps while the keyboard rises in its place.
  double _reserve = 0;
  Timer? _reserveTimer;

  Future<void> _openRunningAgent(RunningAgent selected) async {
    if (!mounted) return;
    final agent = selected.item;
    // A subagent shows its own run (its steps, live), as on the desktop; a
    // command, or a subagent whose card is not in the history held, its task.
    if (agent == null) {
      final task = selected.task;
      if (task == null) return;
      await openPage<void>(
        context,
        TaskPage(
          state: widget.state,
          desktopId: widget.desktopId,
          sessionId: _sessionId,
          task: task,
        ),
      );
      return;
    }
    openSubagentPage(
      context,
      state: widget.state,
      desktopId: widget.desktopId,
      projectId: widget.projectId,
      sessionId: _sessionId,
      item: agent,
    );
  }
}
