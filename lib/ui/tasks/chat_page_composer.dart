// ignore_for_file: invalid_use_of_protected_member
part of 'chat_page.dart';

/// 输入区：两种输入栏、附件、粘贴、面板和本地排队。
extension _Composer on _ChatPageState {
  /// Whether a message sent now waits on the phone: the agent is at work, or
  /// messages queued earlier have not gone out yet (a new one must not pass
  /// them).
  bool get _queueing =>
      _buffer.live ||
      widget.state.localQueue.messages(widget.desktopId, _sessionId).isNotEmpty;

  /// 清空输入：文字、待发图片和 @ 提及。正在编辑时只清内容，不退出编辑。
  void _clearInput() {
    if (_composer.text.trim().isEmpty && _images.isEmpty) return;
    setState(() {
      _images.clear();
      _mentions.clear();
      _imagesMissing = false;
      _composer.clear();
    });
    if (_editIndex == null) _saveDraft('');
  }

  /// 有东西可清时才出现的橡皮。
  Widget _clearButton() => ValueListenableBuilder<TextEditingValue>(
    valueListenable: _composer,
    builder: (context, value, _) => value.text.trim().isEmpty && _images.isEmpty
        ? const SizedBox.shrink()
        : IconButton(
            tooltip: tr('清空输入', 'Clear input'),
            onPressed: _clearInput,
            color: Theme.of(context).colorScheme.error,
            icon: const LucideIcon('eraser', size: 22),
          ),
  );

  /// Puts the draft on the phone's queue and clears the input; nothing is
  /// sent until the turn ends.
  void _queueDraft() {
    final text = _composer.text;
    widget.state.localQueue.add(
      widget.desktopId,
      _sessionId,
      text: text,
      images: List.of(_images),
      mentions: _mentions.where((path) => text.contains('@$path')).toList(),
      project: widget.projectId,
      bot: widget.botId,
    );
    setState(() {
      _error = null;
      _images.clear();
      _mentions.clear();
      _composer.clear();
    });
    _saveDraft('');
  }

  Future<void> _localNow(LocalQueuedMessage message) async {
    if (!_online || _sending) return;
    final sent = await widget.state.localQueue.sendNow(
      widget.desktopId,
      _sessionId,
      message.id,
    );
    if (sent && mounted) _forceBottom();
  }

  /// Takes the message back into the input, with its pictures and files. A
  /// draft already there is kept: the message is added after it.
  void _localEdit(LocalQueuedMessage message) {
    final taken = widget.state.localQueue.take(
      widget.desktopId,
      _sessionId,
      message.id,
    );
    if (taken == null) {
      setState(
        () => _error = tr(
          '这条消息已经在发送或已移出队列。',
          'That message is being sent or already left the queue.',
        ),
      );
      return;
    }
    final draft = _composer.text.trim();
    _images.addAll(taken.images);
    _mentions.addAll(taken.mentions);
    _composer.text = draft.isEmpty ? taken.text : '$draft\n${taken.text}';
    _composer.selection = TextSelection.collapsed(
      offset: _composer.text.length,
    );
    _draftChanged();
    _composerFocus.requestFocus();
  }

  void _localRemove(LocalQueuedMessage message) {
    widget.state.localQueue.take(widget.desktopId, _sessionId, message.id);
  }

  /// 输入框上方显示连接、编辑提示，以及发送后等待执行的消息。
  List<Widget> _composerNotices() {
    final queue = widget.state.localQueue;
    final held = _hasSession
        ? queue.messages(widget.desktopId, _sessionId).length
        : 0;
    final failure = _hasSession
        ? queue.failure(widget.desktopId, _sessionId)
        : null;
    final offline = [
      if (!_online)
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _composer,
          builder: (context, value, _) {
            final hasDraft = value.text.trim().isNotEmpty || _images.isNotEmpty;
            if (!hasDraft && held == 0) return const SizedBox.shrink();
            final status = _status;
            return ComposerNotice(
              key: const ValueKey('offline-notice'),
              icon: 'plug',
              title: switch (status) {
                DesktopLinkStatus.connecting => tr(
                  '正在连接电脑，连上后才能发送',
                  'Connecting; you can send once connected',
                ),
                DesktopLinkStatus.needsPairing => tr(
                  '需要重新配对才能发送',
                  'Pair again to send',
                ),
                _ => tr('未连接电脑，暂时发不出去', 'Not connected; cannot send yet'),
              },
              detail: switch ((hasDraft, held > 0)) {
                (true, true) => tr(
                  '草稿和排队消息已保留',
                  'draft and queued messages kept',
                ),
                (false, true) => tr(
                  '排队消息已保留，连上后继续发送',
                  'queued messages kept, sent once connected',
                ),
                _ => tr('草稿已保留', 'draft kept'),
              },
              actionLabel: status == DesktopLinkStatus.offline
                  ? tr('重试', 'Retry')
                  : null,
              onAction: status == DesktopLinkStatus.offline
                  ? () => widget.state.retryConnection(widget.desktopId)
                  : null,
            );
          },
        ),
      // What the queue could not send stays queued; the user says when to try again.
      if (failure != null && _online)
        ComposerNotice(
          key: const ValueKey('queue-failure-notice'),
          icon: 'triangle-alert',
          tone: Theme.of(context).colorScheme.error,
          title: failure,
          actionLabel: tr('重试', 'Retry'),
          onAction: () => queue.retry(widget.desktopId, _sessionId),
        ),
    ];
    if (_editIndex != null) return offline;
    final rows = _hasSession
        ? queue.messages(widget.desktopId, _sessionId)
        : const <LocalQueuedMessage>[];
    return [
      ...offline,
      if (rows.isNotEmpty)
        QueuedMessagesPanel(
          messages: rows,
          tr: tr,
          enabled:
              _online &&
              !_commandBusy &&
              !_sending &&
              !queue.busy(widget.desktopId, _sessionId),
          onSendNow: _localNow,
          onEdit: _localEdit,
          onRemove: _localRemove,
        ),
    ];
  }

  /// The input card's own first line while a sent message is edited, so it
  /// reads as the composer's state rather than as the chat's.
  Widget _editHeader(SessionBuffer buffer) => Padding(
    padding: const EdgeInsets.only(left: MobileSpace.sm),
    child: ComposerNotice(
      key: const ValueKey('editing-notice'),
      icon: 'pencil',
      tone: _editValid
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.error,
      title: _editValid
          ? tr('正在编辑', 'Editing')
          : tr('编辑的消息已变化', 'The message changed'),
      detail: !_editValid
          ? tr('请取消后重新选择', 'Cancel and select it again')
          : buffer.loading
          ? tr('正在同步对话', 'Syncing the conversation')
          : buffer.live
          ? tr('将中断并丢弃后续', 'Stops this turn, drops what follows')
          : tr('后续对话将被丢弃', 'Drops what follows'),
      actionLabel: tr('取消', 'Cancel'),
      onAction: _sending ? null : _cancelEdit,
    ),
  );

  Future<void> _paste() async {
    if (_pasting) return;
    _pasting = true;
    final before = _composer.value;
    final generation = _binding.generation;
    final editing = _editAnchor;
    try {
      final content = await ChatClipboard.read();
      final text =
          content?.text ??
          (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (!mounted || (text == null && content == null)) return;
      if (generation != _binding.generation ||
          editing != _editAnchor ||
          _composer.value != before) {
        setState(
          () => _error = tr(
            '输入内容已变化，请重新粘贴。',
            'The input changed. Please paste again.',
          ),
        );
        return;
      }
      final selection = before.selection;
      final start = selection.isValid ? selection.start : before.text.length;
      final end = selection.isValid ? selection.end : before.text.length;
      _images.addAll([
        for (final image in content?.images ?? const <ImageAttachment>[])
          DraftImage(image.name ?? 'image', image.mediaType, image.bytes),
      ]);
      _composer.value = TextEditingValue(
        text: before.text.replaceRange(start, end, text ?? ''),
        selection: TextSelection.collapsed(offset: start + (text?.length ?? 0)),
      );
      _draftChanged();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(
            '无法粘贴图文，请重新复制后再试。',
            'Could not paste the message. Copy it again and retry.',
          ),
        );
      }
    } finally {
      _pasting = false;
    }
  }

  Widget _pasteScope(Widget child) => Actions(
    actions: {
      PasteTextIntent: CallbackAction<PasteTextIntent>(
        onInvoke: (_) {
          unawaited(_paste());
          return null;
        },
      ),
    },
    child: child,
  );

  Widget _pasteMenu(BuildContext context, EditableTextState editable) {
    final items = editable.contextMenuButtonItems;
    final paste = ContextMenuButtonItem(
      type: ContextMenuButtonType.paste,
      onPressed: () {
        editable.hideToolbar();
        unawaited(_paste());
      },
    );
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editable.contextMenuAnchors,
      buttonItems: [
        for (final item in items)
          item.type == ContextMenuButtonType.paste ? paste : item,
        if (!items.any((item) => item.type == ContextMenuButtonType.paste))
          paste,
      ],
    );
  }

  Future<void> _pickImages({ImageSource? source}) async {
    _composerFocus.unfocus();
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final List<XFile> files;
      if (source == ImageSource.camera) {
        final file = await ImagePicker().pickImage(source: ImageSource.camera);
        files = file == null ? [] : [file];
      } else {
        files = await ImagePicker().pickMultiImage();
      }
      final picked = <DraftImage>[];
      for (final file in files) {
        if (await file.length() >= LinkLimits.image) {
          throw UserFacingError(
            tr('每张图片必须小于 8 MB', 'Each image must be under 8 MB'),
          );
        }
        final bytes = await file.readAsBytes();
        if (4 * ((bytes.length + 2) ~/ 3) >= LinkLimits.image) {
          throw UserFacingError(
            tr(
              '图片的 base64 数据必须小于 8 MB',
              'Base64 image data must be under 8 MB',
            ),
          );
        }
        final type =
            file.mimeType ??
            switch (file.name.toLowerCase().split('.').last) {
              'png' => 'image/png',
              'gif' => 'image/gif',
              'webp' => 'image/webp',
              'jpg' || 'jpeg' => 'image/jpeg',
              _ => '',
            };
        if (![
          'image/png',
          'image/jpeg',
          'image/gif',
          'image/webp',
        ].contains(type)) {
          throw UserFacingError(tr('不支持此图片格式', 'Unsupported image format'));
        }
        picked.add(DraftImage(file.name, type, bytes));
      }
      if (mounted && picked.isNotEmpty) {
        _images.addAll(picked);
        _draftChanged();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = userMessage(widget.state, error));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// 和文件页同一个浏览：一层层点进项目，点到文件就把它 @ 进输入框。
  /// 回来以后像选完图片一样把键盘叫回来。
  Future<void> _mention() async {
    _composerFocus.unfocus();
    final project = _project;
    if (project == null) return;
    final selected = await openPage<String>(
      context,
      FilesPage(state: widget.state, project: project, picking: true),
    );
    if (!mounted) return;
    _composerFocus.requestFocus();
    if (selected == null) return;
    _mentions.add(selected);
    final selection = _composer.selection;
    final start = selection.isValid ? selection.start : _composer.text.length;
    final end = selection.isValid ? selection.end : start;
    final insert = '@$selected ';
    _composer.value = TextEditingValue(
      text: _composer.text.replaceRange(start, end, insert),
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
  }

  /// 输入框以 `/` 开头时的命令列表：内置的常用命令、电脑上的技能和项目命令。
  Widget _slashMenu({bool force = false, VoidCallback? onPicked}) {
    final query = _editIndex == null
        ? force ? '' : slashQuery(_composer.text)
        : null;
    if (query == null) return const SizedBox.shrink();
    if ((_projectCommands == null || _skills == null) &&
        _online &&
        !clock.now().isBefore(_desktopCommandsDue)) {
      unawaited(_loadDesktopCommands());
    }
    final matches = matchSlashCommands([
      ...builtinSlashCommands(tr),
      ...?_projectCommands,
      ...?_skills,
    ], query);
    if (matches.isEmpty) return const SizedBox.shrink();
    return SlashCommandMenu(
      commands: matches,
      projectLabel: tr('项目', 'Project'),
      onPick: (command) {
        final current = _composer.text;
        final argument = force && !current.trimLeft().startsWith('/') ? current : '';
        final text = '/${command.name} $argument';
        _composer.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        onPicked?.call();
        _composerFocus.requestFocus();
      },
    );
  }

  /// 只问还没拿到的那份；没拿全的，[_desktopCommandsRetry] 之后再打 `/` 时重问。
  Future<void> _loadDesktopCommands() async {
    _desktopCommandsDue = DateTime(9999);
    final (commands, skills) = await (
      _projectCommands == null
          ? _loadProjectCommands()
          : Future.value(_projectCommands),
      _skills == null ? _loadSkills() : Future.value(_skills),
    ).wait;
    _desktopCommandsDue = clock.now().add(_desktopCommandsRetry);
    if (!mounted) return;
    setState(() {
      _projectCommands = commands;
      _skills = skills;
    });
  }

  static const _desktopCommandsRetry = Duration(seconds: 10);

  /// 拿不到（断线、超时）是 null；电脑端太旧不认 `extensions` 就当没有。
  Future<List<SlashCommand>?> _loadSkills() async {
    try {
      final result = await widget.state.request(
        widget.desktopId,
        LinkMethods.extensions,
      );
      return [
        for (final item in (objectMap(result)['items'] as List?) ?? const [])
          if (LinkExtension.fromJson(objectMap(item)) case final skill
              when skill.kind == 'skill' &&
                  skill.enabled != false &&
                  (skill.project == null || skill.project == widget.projectId))
            SlashCommand(
              skill.name,
              skill.description,
              kind: SlashKind.skill,
              project: skill.project != null,
            ),
      ];
    } on LinkRemoteException catch (error) {
      return error.code == LinkErrors.unknown ? const [] : null;
    } on Object {
      return null;
    }
  }

  /// 项目 `.claude/commands` 下的命令文件，经电脑的 `folder`、`read` 读来；
  /// 拿不到（断线、超时）是 null。
  Future<List<SlashCommand>?> _loadProjectCommands() async {
    final project = widget.projectId;
    if (project == null) return const [];
    const folder = '.claude/commands';
    final Map<String, Object?> listing;
    try {
      listing = objectMap(
        await widget.state.request(widget.desktopId, LinkMethods.folder, {
          'project': project,
          'path': folder,
        }),
      );
    } on LinkRemoteException catch (error) {
      // 没有这个文件夹，或电脑端还不认 `folder`。
      return error.code == LinkErrors.notFound ||
              error.code == LinkErrors.unknown
          ? const []
          : null;
    } on Object {
      return null;
    }
    final names = [
      for (final name in (listing['files'] as List?) ?? const [])
        if (name is String && name.endsWith('.md')) name,
    ].take(_maxProjectCommands);
    try {
      final read = await Future.wait([
        for (final name in names) _readProjectCommand(project, folder, name),
      ]);
      return [...read.nonNulls];
    } on Object {
      return null;
    }
  }

  Future<SlashCommand?> _readProjectCommand(
    String project,
    String folder,
    String name,
  ) async {
    try {
      final file = objectMap(
        await widget.state.request(widget.desktopId, LinkMethods.read, {
          'project': project,
          'path': '$folder/$name',
        }),
      );
      return switch (file['text']) {
        final String text => projectSlashCommand(name, text),
        _ => null,
      };
    } on LinkRemoteException catch (error) {
      // 列出来之后被删了。
      if (error.code == LinkErrors.notFound) return null;
      rethrow;
    }
  }

  static const _maxProjectCommands = 50;

  /// 输入框的底：白底、一圈细边、圆角。上面那排摘要单独一块，不在这块里。
  BoxDecoration get _composerDecoration => BoxDecoration(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    border: Border.all(
      color: Theme.of(context).colorScheme.onSurfaceVariant
          .withValues(alpha: .18),
    ),
    borderRadius: BorderRadius.circular(22),
  );

  Widget _draftImages() {
    // 待发附件共用一个画廊；移除某张后组随之重建。
    final group = [
      for (final image in _images) GalleryImage(image.bytes, name: image.name),
    ];
    return _draftImageStrip(group);
  }

  Widget _draftImageStrip(List<GalleryImage> group) {
    // Bot 的缩略图更紧凑，仍共享图片草稿与移除逻辑。
    final bot = widget.botId != null;
    final thumbnail = bot ? 64.0 : 76.0;
    final bottom = bot ? 0.0 : 8.0;
    return SizedBox(
      height: thumbnail + 8 + bottom,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(12, 8, 12, bottom),
        scrollDirection: Axis.horizontal,
        itemCount: _images.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => SizedBox.square(
          dimension: thumbnail,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(bot ? 6 : 12),
                child: MemoryPicture(
                  bytes: _images[i].bytes,
                  name: _images[i].name,
                  group: group,
                  index: i,
                  width: thumbnail,
                  height: thumbnail,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(right: 0, top: 0, child: _removeImageBadge(i)),
            ],
          ),
        ),
      ),
    );
  }

  /// 缩略图角上的小角标；看着小，点击区比它大一圈。
  Widget _removeImageBadge(int index) => Tooltip(
    message: tr('移除图片', 'Remove image'),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _sending
          ? null
          : () {
              _images.removeAt(index);
              _draftChanged();
            },
      child: SizedBox.square(
        dimension: 28,
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Container(
              key: const ValueKey('draft-image-remove'),
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  );

  /// 运行中的独立停止操作，不因输入或排队消息而消失。
  Widget _stopAction({required double size}) => StopActionButton(
    busy: _commandBusy,
    size: size,
    iconSize: 26,
    tooltip: _commandBusy
        ? tr('正在停止…', 'Stopping…')
        : tr('停止生成', 'Stop generation'),
    onPressed: () => _command(LinkMethods.stop),
  );

  /// 加号面板里每格的图标边，和微信差不多大。
  static const _addTile = 60.0;

  /// 一行四列，从左往右填，填满再换行。
  static const _addColumns = 4;

  double get _keyboardHeight => _seenKeyboard ?? 280;

  double get _panelHeight =>
      math.min(_keyboardHeight, MediaQuery.sizeOf(context).height * .5);

  void _closeAdd() {
    if (_addOpen) setState(() => _addOpen = false);
  }

  /// Closes the panel for the keyboard: its room shrinks as the keyboard
  /// rises, so the composer stays put.
  void _addToKeyboard() {
    if (!_addOpen) return;
    setState(() {
      _addOpen = false;
      _reserve = _panelHeight;
    });
    _reserveTimer?.cancel();
    _reserveTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _reserve = 0);
    });
  }

  Future<void> _toggleAdd() async {
    if (_actionsOpen) return;
    _composerFocus.unfocus();
    _closeAdd();
    setState(() {
      _actionsOpen = true;
      _reserve = 0;
    });
    final sheet = showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      requestFocus: false,
      builder: (sheetContext) => AnimatedBuilder(
        animation: widget.state,
        builder: (_, _) => _addPanel(
          sheetContext,
          _online && !_sending && !_picking,
        ),
      ),
    );
    // 这个弹层也包含会话设置；普通草稿沿用打开设置时才建立会话的规则。
    if (widget.botId == null && !_hasSession && _online && _project != null) {
      unawaited(runUi(context, () async {
        await _ensureSession();
        if (mounted) await _binding.settled;
      }, errorMessage: (error) => userMessage(widget.state, error)));
    }
    try {
      await sheet;
    } finally {
      if (mounted) setState(() => _actionsOpen = false);
    }
  }

  Future<void> _openSlashMenu() async {
    final loading = (_projectCommands == null || _skills == null) &&
            _online && !clock.now().isBefore(_desktopCommandsDue)
        ? _loadDesktopCommands()
        : Future<void>.value();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      requestFocus: false,
      builder: (sheetContext) => FutureBuilder<void>(
        future: loading,
        builder: (_, _) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
          child: SingleChildScrollView(
            child: _slashMenu(
              force: true,
              onPicked: () => Navigator.pop(sheetContext),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleEmoji() => _togglePanel(emoji: true);

  /// 点当前面板的按钮回到键盘；另一个面板开着时直接切换。
  void _togglePanel({required bool emoji}) {
    if (_addOpen && _emojiPanel == emoji) {
      _addToKeyboard();
      _composerFocus.requestFocus();
    } else {
      _composerFocus.unfocus();
      _reserveTimer?.cancel();
      setState(() {
        _addOpen = true;
        _emojiPanel = emoji;
        _reserve = 0;
      });
    }
  }

  void _insertEmoji(String emoji) {
    final value = _composer.value;
    final at = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    _composer.value = TextEditingValue(
      text: value.text.replaceRange(at.start, at.end, emoji),
      selection: TextSelection.collapsed(offset: at.start + emoji.length),
    );
  }

  /// 退一格：选中的文字，或光标前一个完整字符（表情可能占多个码元）。
  void _deleteBackward() {
    final value = _composer.value;
    final at = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final before = at.isCollapsed
        ? value.text.substring(0, at.start).characters.skipLast(1).string
        : value.text.substring(0, at.start);
    _composer.value = TextEditingValue(
      text: before + value.text.substring(at.end),
      selection: TextSelection.collapsed(offset: before.length),
    );
  }

  Widget _composerView(SessionBuffer buffer, bool ready) {
    if (_composerFocus.hasFocus) {
      final inset = MediaQuery.viewInsetsOf(context).bottom;
      if (inset > math.max(_seenKeyboard ?? 0, 100)) _seenKeyboard = inset;
    }
    final bot = widget.botId != null;
    final live = buffer.live && _online;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (bot && live) BotWorkingLine(tr: tr, since: _turnStart(buffer)),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ..._composerNotices(),
              if (_hasSession && !bot)
                ChatActivityCard(
                  key: ValueKey((widget.desktopId, _sessionId)),
                  state: widget.state,
                  desktopId: widget.desktopId,
                  sessionId: _sessionId,
                  projectId: widget.projectId,
                  agents: projectRunningAgents(
                    buffer.items.map(ChatCodec.decode).whereType<ChatItem>(),
                    buffer.tasks,
                  ),
                  onOpenAgent: _openRunningAgent,
                  foldSignal: _trayFold,
                ),
              if (!bot) _slashMenu(),
              DecoratedBox(
                key: const ValueKey('composer-input-surface'),
                decoration: _composerDecoration,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_editIndex != null) _editHeader(buffer),
                    if (_images.isNotEmpty) _draftImages(),
                    _pasteScope(
                      TextField(
                        controller: _composer,
                        focusNode: _composerFocus,
                        contextMenuBuilder: _pasteMenu,
                        groupId: _addRegion,
                        onTap: _addToKeyboard,
                        style: Theme.of(context).textTheme.bodyMedium,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          suffixIcon: _clearButton(),
                          suffixIconConstraints: const BoxConstraints(),
                          contentPadding: EdgeInsets.fromLTRB(
                            16,
                            _editIndex != null ? 2 : 14,
                            16,
                            2,
                          ),
                          hintText: bot
                              ? tr('发消息…', 'Message…')
                              : tr('发消息，@files， /command', 'Message, @files, /command'),
                        ),
                      ),
                    ),
                    _composerToolbar(buffer, ready, live),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (bot && _addOpen && _emojiPanel && !_sending)
          TapRegion(
            groupId: _addRegion,
            onTapOutside: (_) => _closeAdd(),
            child: SizedBox(
              key: const ValueKey('chat-emoji'),
              height: math.max(0, _panelHeight - MediaQuery.viewInsetsOf(context).bottom),
              child: EmojiPanel(
                composer: _composer,
                canSend: () => ready && !_imagesMissing && _editReady,
                onPick: _insertEmoji,
                onDelete: _deleteBackward,
                onSend: _send,
                deleteLabel: tr('删除', 'Delete'),
                sendLabel: tr('发送', 'Send'),
              ),
            ),
          ),
        if (!_addOpen && _reserve > 0)
          SizedBox(
            height: math.max(0, _reserve - MediaQuery.viewInsetsOf(context).bottom),
          ),
      ],
    );
  }

  Widget _composerToolbar(SessionBuffer buffer, bool ready, bool live) {
    final usage = ContextUsage.parse(buffer.context);
    final add = TapRegion(
      groupId: _addRegion,
      child: IconButton(
        key: const ValueKey('composer-add'),
        tooltip: tr('更多输入选项', 'More input options'),
        onPressed: _sending || _picking ? null : _toggleAdd,
        icon: const LucideIcon('plus', size: 22),
      ),
    );
    Widget contextUsage() => usage == null
        ? const SizedBox.shrink()
        : ContextRing(
            state: widget.state,
            usage: usage,
            showValue: true,
            onPressed: () => showContextUsage(context, widget.state, usage),
          );
    return LayoutBuilder(
      builder: (context, constraints) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: _composer,
        builder: (context, value, _) {
          final hasDraft = value.text.trim().isNotEmpty || _images.isNotEmpty;
          final canSend = ready && !_sending && hasDraft && !_imagesMissing && _editReady;
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (live) _stopAction(size: 48),
              if (!live || hasDraft || _sending)
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 8),
                  child: ChatComposerAction(
                    busy: _sending,
                    enabled: canSend,
                    tooltip: _editIndex != null ? tr('重新发送', 'Resend') : tr('发送', 'Send'),
                    onSend: _send,
                  ),
                ),
            ],
          );
          final crowded = constraints.maxWidth < 330 ||
              MediaQuery.textScalerOf(context).scale(14) > 18;
          if (crowded) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [add, Expanded(child: _modelButton(ready))]),
                Row(children: [const Spacer(), contextUsage(), actions]),
              ],
            );
          }
          return Row(
            children: [add, Expanded(child: _modelButton(ready)), contextUsage(), actions],
          );
        },
      ),
    );
  }

  Widget _addPanel(BuildContext sheetContext, bool ready) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final bot = widget.botId != null;
    final buffer = _buffer;
    final blocked = _picking || _sending || !_binding.available;
    final permission = buffer.choices.where((choice) => choice.kind == 'permission').firstOrNull;
    final mode = buffer.choices.where((choice) => choice.kind == 'mode').firstOrNull;
    final session = _sessionId;
    final generation = _binding.generation;
    void pick(VoidCallback action, bool focus) {
      Navigator.pop(sheetContext);
      if (!mounted) return;
      action();
      if (focus) _composerFocus.requestFocus();
    }
    final actions = <(String, String, String, VoidCallback?, bool)>[
      ('album', 'images', tr('相册', 'Photos'), blocked ? null : _pickImages, true),
      ('camera', 'camera', tr('拍照', 'Camera'),
          blocked ? null : () => _pickImages(source: ImageSource.camera), true),
      if (!bot) ...[
        ('file', 'at-sign', tr('@ 文件', '@ Files'),
            ready && _project != null ? _mention : null, true),
        ('command', 'slash', tr('斜杠命令', 'Commands'),
            blocked || _editIndex != null ? null : () => runUi(context, _openSlashMenu,
                errorMessage: (error) => userMessage(widget.state, error)), false),
      ] else
        ('emoji', 'smile', tr('表情', 'Emoji'), blocked ? null : _toggleEmoji, false),
    ];
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * .72),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0, side = 16.0;
            final width = ((constraints.maxWidth - side * 2 - gap * (_addColumns - 1)) /
                _addColumns).floorToDouble();
            final tile = math.min(media.textScaler.scale(_addTile), width);
            return SingleChildScrollView(
              key: const ValueKey('chat-actions'),
              padding: const EdgeInsets.fromLTRB(side, 20, side, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final (id, icon, title, onTap, focus) in actions)
                        SizedBox(
                          key: ValueKey('chat-action-$id'),
                          width: width,
                          child: Tooltip(
                            message: title,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: onTap == null ? null : () => pick(onTap, focus),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: tile,
                                      height: tile,
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerLowest,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Center(
                                        child: LucideIcon(icon, size: tile * .44,
                                            color: onTap == null ? scheme.onSurfaceVariant : scheme.onSurface),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: MobileType.secondary,
                                            color: scheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (!bot && permission != null && permission.options.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _settingRow(permission, ready),
                  ],
                  if (!bot && mode != null && mode.options.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(tr('模式', 'Mode'), style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    IgnorePointer(
                      ignoring: !ready || _commandBusy,
                      child: SegmentBar<String>(
                        key: const ValueKey('composer-mode'),
                        values: [for (final option in mode.options) option.id],
                        selected: mode.selected ?? '',
                        label: (id) => _choicePresentation('mode',
                            mode.options.firstWhere((option) => option.id == id)).$1,
                        onSelected: (option) {
                          if (!mounted || !ready || !_online || _commandBusy || !_hasSession ||
                              _sessionId != session || _binding.generation != generation) return;
                          runUi(context, () => _command(LinkMethods.choose,
                              {'kind': 'mode', 'option': option}),
                              errorMessage: (error) => userMessage(widget.state, error));
                        },
                      ),
                    ),
                  ],
                  if (!bot)
                    for (final choice in _visibleChoices(buffer))
                      if (!{'model', 'mode', 'permission'}.contains(choice.kind)) ...[
                        const SizedBox(height: 16),
                        _settingRow(choice, ready),
                      ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _settingRow(LinkChoice choice, bool ready) => Builder(
    builder: (anchor) => InkWell(
      key: ValueKey('composer-setting-${choice.kind}'),
      onTap: ready && !_commandBusy && _hasSession
          ? () => runUi(context, () => _choices(anchor, choice),
              errorMessage: (error) => userMessage(widget.state, error))
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Text(_choiceLabel(choice.kind)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(_chipValue(choice), textAlign: TextAlign.right,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            const LucideIcon('chevron-right', size: 18),
          ],
        ),
      ),
    ),
  );
}
