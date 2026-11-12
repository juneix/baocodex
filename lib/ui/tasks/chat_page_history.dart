// ignore_for_file: invalid_use_of_protected_member
part of 'chat_page.dart';

/// 历史消息列表：跟随、翻页、在自己的消息之间跳转。
extension _History on _ChatPageState {
  /// Follows the end of the stream. Never while the user has a finger on the
  /// list or is flinging it: their scroll decides, not the content growing.
  void _bottom([int settle = 4]) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients || _userScrolling || !_follow) {
          return;
        }
        final position = _scroll.position;
        if (position.pixels != position.maxScrollExtent) {
          _scroll.jumpTo(position.maxScrollExtent);
        }
        // Rows not built yet are estimated: the end moves once they are laid
        // out, so look again next frame.
        if (settle > 0) _bottom(settle - 1);
      });

  /// Rows not built yet are estimated, so the end moves as they are laid out:
  /// it counts as reached once it stays put for a frame.
  void _placeAtBottom([double? lastEnd, int frames = 12]) {
    _placing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scroll.hasClients) {
        _placing = false;
        return;
      }
      final end = _scroll.position.maxScrollExtent;
      if (_scroll.position.pixels != end) _scroll.jumpTo(end);
      if (end == lastEnd || frames == 0) {
        setState(() => _placed = true);
        return;
      }
      _placeAtBottom(end, frames - 1);
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  /// The user's own message: back to the end and following again.
  void _forceBottom() {
    _userScrolling = false;
    _setFollow(true);
    _bottom();
  }

  void _setFollow(bool follow) {
    _follow = follow;
    if (_away.value == follow) _away.value = !follow;
    if (!follow) {
      _holdRunningTurn();
    } else if (_keepOpenFrom != null) {
      setState(() => _keepOpenFrom = null);
    }
  }

  void _holdRunningTurn() {
    if (!_buffer.live) return;
    _keepOpenFrom ??= _rows
        .where(
          (row) => switch (row.shown) {
            UserMessageItem(queued: false) => true,
            _ => false,
          },
        )
        .lastOrNull
        ?.index;
  }

  /// Whether the user is dragging or flinging the list, and where they leave
  /// it. Only their scrolling moves [_follow]: the list growing under a
  /// streaming reply, or our own `jumpTo`, never does.
  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final was = _userScrolling;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrolling = true;
      _jumpTicket++;
      _trayFold.value++;
    } else if (notification is UserScrollNotification) {
      _userScrolling = notification.direction != ScrollDirection.idle;
    }
    if (_userScrolling || was) {
      final metrics = notification.metrics;
      final delta = switch (notification) {
        ScrollUpdateNotification(:final scrollDelta) => scrollDelta ?? 0.0,
        OverscrollNotification(:final overscroll) => overscroll,
        _ => 0.0,
      };
      final towardEarlier = delta < 0;
      final fromEnd = metrics.maxScrollExtent - metrics.pixels;
      // 往上翻一点就不再跟随；往下回到底部附近才重新跟随。
      if (towardEarlier && fromEnd > 16) {
        _setFollow(false);
      } else if (delta > 0 && fromEnd < 100) {
        _setFollow(true);
      }
      if (towardEarlier &&
          metrics.extentBefore < 160 &&
          _earlierError == null) {
        unawaited(_earlier());
      }
    }
    return false;
  }

  /// The list's height changes under the keyboard or what docks over the
  /// composer: what sat just above the composer stays there.
  bool _onViewport(ScrollMetricsNotification notification) {
    if (notification.depth != 0) return false;
    final height = notification.metrics.viewportDimension;
    final before = _viewport;
    _viewport = height;
    if (before == null || before == height || _userScrolling) return false;
    if (_follow) {
      _bottom();
    } else {
      final shrunk = before - height;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final position = _scroll.position;
        _scroll.jumpTo(
          (position.pixels + shrunk).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      });
    }
    return false;
  }

  Future<void> _jumpToBottom() async {
    if (!_scroll.hasClients) return;
    _userScrolling = false;
    _setFollow(true);
    await _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    // Unbuilt rows are estimated, so the end moved while it ran: 等这一帧排完
    // 再对一次，最后一条的下边距这时才算进去。
    if (mounted && _scroll.hasClients && _follow) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients || !_follow) return;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  (String, int) _historyRowId(ChatRow row) => (
    row.edits != null
        ? 'edits'
        : row.work != null
        ? 'work'
        : row.steps != null
        ? 'steps'
        : 'message',
    row.index,
  );

  (GlobalKey, double)? _historyAnchor() {
    final viewport = _historyListKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    (GlobalKey, double)? anchor;
    for (final key in _historyRowKeys.values) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y + box.size.height > top &&
          y < bottom &&
          (anchor == null || y < anchor.$2)) {
        anchor = (key, y);
      }
    }
    return anchor;
  }

  void _preserveReadingPosition() {
    if (_follow) {
      _bottom();
      return;
    }
    final anchor = _historyAnchor();
    final generation = _binding.generation;
    if (anchor == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _binding.generation ||
          !_scroll.hasClients) {
        return;
      }
      final box = anchor.$1.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      final target =
          _scroll.offset + box.localToGlobal(Offset.zero).dy - anchor.$2;
      _scroll.jumpTo(
        target.clamp(
          _scroll.position.minScrollExtent,
          _scroll.position.maxScrollExtent,
        ),
      );
    });
  }

  /// 同一时间只取一页；已在取时，等的是同一次。[keepFollow]：提前取不算
  /// 用户往回看，停在底部的仍要跟着新内容走。
  Future<void> _earlier({bool keepFollow = false}) =>
      _earlierLoad ??= _loadEarlier(keepFollow: keepFollow).whenComplete(() {
        _earlierLoad = null;
      });

  Future<void> _loadEarlier({required bool keepFollow}) async {
    final buffer = _buffer;
    if (_loadingEarlier ||
        buffer.loadingEarlier ||
        buffer.loading ||
        buffer.earlier != true ||
        !_online ||
        _editIndex != null) {
      return;
    }
    final generation = _binding.generation;
    final first = buffer.items.firstOrNull;
    if (!keepFollow) _setFollow(false);
    setState(() {
      _loadingEarlier = true;
      _earlierError = null;
    });
    try {
      await widget.state.loadEarlier(widget.desktopId, _sessionId);
      if (!mounted || generation != _binding.generation) return;
      if (buffer.error case final error?) {
        setState(() => _earlierError = error);
        return;
      }
      final added = first == null ? 0 : buffer.items.indexOf(first);
      if (added <= 0) return;
      _centerItem += added;
      _historyRowKeys = {
        for (final entry in _historyRowKeys.entries)
          (entry.key.$1, entry.key.$2 + added): entry.value,
      };
      if (_keepOpenFrom case final from?) _keepOpenFrom = from + added;
      final folds = Map.of(_foldsOpen);
      _foldsOpen
        ..clear()
        ..addEntries(
          folds.entries.map(
            (entry) =>
                MapEntry((entry.key.$1, entry.key.$2 + added), entry.value),
          ),
        );
    } catch (error) {
      if (mounted && generation == _binding.generation) {
        setState(() => _earlierError = userMessage(widget.state, error));
      }
    } finally {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  /// The nearest message of mine before or after the wire [index].
  ChatRow? _nearestMine(int index, {required bool up}) {
    final mine = _rows.where(
      (row) => !row.isFold && row.showItem && row.shown is UserMessageItem,
    );
    return up
        ? mine.where((row) => row.index < index).lastOrNull
        : mine.where((row) => row.index > index).firstOrNull;
  }

  /// 这条已是加载到的最早一条我发的消息：提前取一页，点“上一条”不用等。
  void _preloadEarlier(SessionBuffer buffer) {
    if (buffer.loading || buffer.loadingEarlier || _loadingEarlier) return;
    final first = buffer.items.firstOrNull;
    if (identical(first, _preloadedFrom) || _earlierError != null) return;
    _preloadedFrom = first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_earlier(keepFollow: true));
    });
  }

  Future<void> _jumpMine(int index, {required bool up}) async {
    final generation = _binding.generation;
    final ticket = ++_jumpTicket;
    // 又点了一次、手动滑动或换了对话，这次跳转就作废。
    bool stale() =>
        !mounted ||
        ticket != _jumpTicket ||
        generation != _binding.generation ||
        !_scroll.hasClients;
    var at = index;
    // 上一条还没加载：一页页往前取，直到取到或没有更早的了。
    while (up &&
        _nearestMine(at, up: true) == null &&
        _buffer.earlier == true) {
      final first = _buffer.items.firstOrNull;
      await _earlier();
      while (_buffer.loadingEarlier && !stale()) {
        await WidgetsBinding.instance.endOfFrame;
      }
      await WidgetsBinding.instance.endOfFrame;
      if (stale()) return;
      // 尾部可能同时有新内容，只能按最前面那条的位移算；取不到的原因已显示。
      final added = first == null ? 0 : _buffer.items.indexOf(first);
      if (added <= 0) return;
      at += added;
    }
    final target = _nearestMine(at, up: up);
    if (target == null || stale()) return;
    _setFollow(false);
    final key = _historyRowKeys.putIfAbsent(
      _historyRowId(target),
      GlobalKey.new,
    );
    // 列表是懒加载的：目标还没建出来，就朝它翻屏直到出现。
    while (key.currentContext == null) {
      final position = _scroll.position;
      final next =
          (position.pixels + (up ? -1 : 1) * position.viewportDimension).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          );
      if (next == position.pixels) return;
      _scroll.jumpTo(next);
      await WidgetsBinding.instance.endOfFrame;
      if (stale()) return;
    }
    await Scrollable.ensureVisible(
      key.currentContext!,
      alignment: .04,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  /// A fold line sits on the same 16dp gutter as the message rows around it
  /// (MessageView pads its own rows; these are list children without one).
  Widget _foldPadding(Widget line) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 2, 16, 2), child: line);

  Widget _jumpButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: _away,
      builder: (context, away, _) => Positioned(
        right: 16,
        // 抬高一点，别和输入栏上面那排任务/改动的胶囊挤在一起。
        bottom: 20,
        child: IgnorePointer(
          ignoring: !away,
          child: AnimatedOpacity(
            opacity: away ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Material(
              key: const ValueKey('scroll-to-bottom'),
              color: scheme.surfaceContainerHigh,
              elevation: 3,
              shape: CircleBorder(
                side: BorderSide(color: scheme.outlineVariant),
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _jumpToBottom,
                child: Tooltip(
                  message: tr('回到底部', 'Back to bottom'),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: LucideIcon(
                        'arrow-down',
                        size: 18,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 消息列表，或者还没有消息时该显示的状态。
  Widget _historyArea(
    BuildContext context,
    SessionBuffer buffer,
    List<ChatRow> rows,
    BotRef? bot,
    bool ready,
  ) {
    if (!_placed && !_placing && buffer.items.isNotEmpty) _placeAtBottom();
    if (_centerSession != _sessionId || _centerItem > buffer.items.length) {
      _centerSession = _sessionId;
      _centerItem = 0;
    }
    final firstNewer = rows.indexWhere((row) => row.index >= _centerItem);
    final older = firstNewer < 0 ? rows.length : firstNewer;
    final rowPositions = <Key, int>{
      for (final (position, row) in rows.indexed)
        ?_historyRowKeys[_historyRowId(row)]: position + 1,
    };
    // 每条之前最近的发送时间，决定 Bot 聊天里要不要写时间。
    final previousSent = <int, DateTime>{};
    if (widget.botId != null) {
      DateTime? last;
      for (final (position, row) in rows.indexed) {
        if (last != null) previousSent[position] = last;
        if (row.shown case UserMessageItem(:final sentAt?)) last = sentAt;
      }
    }
    _placeModelMarks(rows, buffer);
    return !_binding.available
        ? EmptyPanel(
            tr(
              '此 Bot 已删除或不可用，未发送任何新操作。',
              'This bot was removed or is unavailable. No new operation was sent.',
            ),
          )
        : buffer.items.isEmpty && (buffer.loading || !_opened)
        ? const Center(child: PixelLoader.agent(size: 28))
        : buffer.items.isEmpty && _hasSession && !_online
        ? EmptyPanel(
            tr(
              '连上电脑后显示这段对话。',
              'This conversation shows once the desktop is connected.',
            ),
          )
        : buffer.items.isEmpty
        ? ChatEmptyState(
            state: widget.state,
            online: _online,
            project: _project,
            bot: widget.botId != null,
            onSwitchProject:
                widget.onSwitchProject == null || _sending
                ? null
                : (anchor) {
                    _composerFocus.unfocus();
                    _closeAdd();
                    unawaited(widget.onSwitchProject!(anchor));
                  },
            canSuggest: !_sending && _composer.text.isEmpty,
            onSuggestion: (text) {
              if (_sending || _composer.text.isNotEmpty) return;
              _composer.text = text;
              _composer.selection = TextSelection.collapsed(
                offset: text.length,
              );
              _composerFocus.requestFocus();
            },
          )
        : Stack(
            children: [
              Positioned.fill(
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: _onViewport,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: Opacity(
                      key: const ValueKey('history-reveal'),
                      opacity: _placed ? 1 : 0,
                      child: CustomScrollView(
                        key: _historyListKey,
                        controller: _scroll,
                        center: const ValueKey('history-center'),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        slivers: [
                          SliverList.builder(
                            itemCount: older,
                            findChildIndexCallback: (key) =>
                                switch (rowPositions[key]) {
                                  final position? when position <= older =>
                                    older - position,
                                  _ => null,
                                },
                            itemBuilder: (context, index) => _historyItem(
                              context,
                              older - index,
                              rows,
                              buffer,
                              bot,
                              ready,
                              previousSent,
                            ),
                          ),
                          SliverPadding(
                            key: const ValueKey('history-center'),
                            padding: const EdgeInsets.only(top: 8),
                            sliver: SliverList.builder(
                              itemCount: rows.length - older,
                              findChildIndexCallback: (key) =>
                                  switch (rowPositions[key]) {
                                    final position? when position > older =>
                                      position - older - 1,
                                    _ => null,
                                  },
                              itemBuilder: (context, index) => _historyItem(
                                context,
                                older + 1 + index,
                                rows,
                                buffer,
                                bot,
                                ready,
                                previousSent,
                                // 最后一条和下面的输入栏之间留一点空，滚到底
                                // 时不至于贴着那块的边。
                                tail: index == rows.length - older - 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              ?_earlierStatus(context, buffer),
              _jumpButton(context),
            ],
          );
  }

  /// 取更早消息的状态浮在列表上，出现和消失都不挪动内容。
  Widget? _earlierStatus(BuildContext context, SessionBuffer buffer) {
    final error = _earlierError;
    if (error == null && !_loadingEarlier && !buffer.loadingEarlier) {
      return null;
    }
    return Positioned(
      top: 8,
      left: 16,
      right: 16,
      child: Center(
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          elevation: 2,
          borderRadius: BorderRadius.circular(MobileSizes.radius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: error == null
                ? Text(tr('加载中…', 'Loading…'))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error),
                      TextButton(
                        onPressed:
                            _online &&
                                !_loadingEarlier &&
                                !buffer.loadingEarlier &&
                                _editIndex == null
                            ? _earlier
                            : null,
                        child: Text(tr('重试', 'Retry')),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _historyItem(
    BuildContext context,
    int position,
    List<ChatRow> rows,
    SessionBuffer buffer,
    BotRef? bot,
    bool ready,
    Map<int, DateTime> previousSent, {
    bool tail = false,
  }) {
    final row = rows[position - 1];
    return KeyedSubtree(
      key: _historyRowKeys.putIfAbsent(_historyRowId(row), GlobalKey.new),
      child: Padding(
        padding: EdgeInsets.only(bottom: tail ? _tailGap : 0),
        child: _withModelMarks(
          position,
          last: position == rows.length,
          Builder(
            builder: (context) {
              if (row.isFold) {
                final key = (row.steps ?? row.work ?? row.edits!).key;
                final expanded = _foldsOpen[key] ?? false;
                void toggle() => setState(() => _foldsOpen[key] = !expanded);
                if (row.edits != null) {
                  return _foldPadding(
                    EditsFoldLine(
                      key: ValueKey('edits-${row.index}'),
                      edits: row.foldItems.whereType<CodeDiffItem>().toList(),
                      expanded: expanded,
                      onToggle: toggle,
                      zh: tr('中', 'en') == '中',
                    ),
                  );
                }
                if (row.work case final work? when widget.botId != null) {
                  return BotWorkFold(
                    key: ValueKey('work-${row.index}'),
                    worked: work.worked ?? Duration.zero,
                    tr: tr,
                    at: row.at,
                    onOpen: row.foldItems.isEmpty
                        ? null
                        : () => openPage<void>(
                            context,
                            BotWorkPage(
                              state: widget.state,
                              desktopId: widget.desktopId,
                              worked: work.worked ?? Duration.zero,
                              items: row.foldItems,
                              bot: bot,
                            ),
                          ),
                  );
                }
                if (row.work case final work?) {
                  return _foldPadding(
                    WorkFoldLine(
                      key: ValueKey('work-${row.index}'),
                      worked: work.worked ?? Duration.zero,
                      edits: turnEdits(row.foldItems),
                      expanded: expanded,
                      onToggle: toggle,
                      strings: FoldStrings(tr('中', 'en') == '中'),
                    ),
                  );
                }
                return _foldPadding(
                  StepsFoldLine(
                    key: ValueKey('steps-${row.index}'),
                    tally: StepTally(row.foldItems),
                    expanded: expanded,
                    onToggle: toggle,
                    strings: FoldStrings(tr('中', 'en') == '中'),
                  ),
                );
              }
              final index = row.index;
              final raw = row.shown ?? row.item;
              final previousTime = previousSent[position - 1];
              final sentAt = raw is UserMessageItem
                  ? raw.sentAt?.toLocal()
                  : null;
              final showTime =
                  widget.botId != null &&
                  sentAt != null &&
                  (previousTime == null ||
                      sentAt.difference(previousTime) >
                          const Duration(minutes: 5));
              final mine = widget.botId == null && raw is UserMessageItem;
              final hasPrevious = mine && _nearestMine(index, up: true) != null;
              final moreEarlier =
                  buffer.earlier == true && _online && _editIndex == null;
              // 没定位好时列表还停在顶上，最早的消息并不真的接近屏幕。
              if (_placed && mine && !hasPrevious && moreEarlier) {
                _preloadEarlier(buffer);
              }
              final canPrevious = hasPrevious || (mine && moreEarlier);
              final canNext = mine && _nearestMine(index, up: false) != null;
              final message = MessageView(
                key: ValueKey(index),
                state: widget.state,
                desktopId: widget.desktopId,
                item: raw,
                bot: bot,
                showMineJump: canPrevious || canNext,
                onPreviousMine: canPrevious
                    ? () => _jumpMine(index, up: true)
                    : null,
                onNextMine: canNext ? () => _jumpMine(index, up: false) : null,
                footer: widget.botId == null ? row.footer : null,
                showItem: row.showItem,
                index: index,
                sessionId: _sessionId,
                projectId: widget.projectId,
                onOpenSession: (id) => openConversation(
                  context,
                  widget.state,
                  desktopId: widget.desktopId,
                  sessionId: id,
                ),
                onEdit: ready && !buffer.loadingEarlier
                    ? (item) => _edit(index, item)
                    : null,
              );
              if (!showTime) return message;
              final now = DateUtils.dateOnly(DateTime.now());
              final day = DateUtils.dateOnly(sentAt);
              final clock = formatClock(sentAt);
              final label = day == now
                  ? clock
                  : day == now.subtract(const Duration(days: 1))
                  ? '${tr('昨天', 'Yesterday')} $clock'
                  : '${formatDay(widget.state, sentAt)} $clock';
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      label,
                      key: const ValueKey('bot-message-time'),
                      style: MobileTheme.metaStyleOf(context),
                    ),
                  ),
                  message,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 换到别的上游的模型（[AppState.modelMarks]）画在哪一行前面：那之后发的
  /// 第一条消息；还没发就在最后一行后面。比已载入的最早一条还早的不画，
  /// 它属于还没翻出来的那一段。
  void _placeModelMarks(List<ChatRow> rows, SessionBuffer buffer) {
    _marksBefore.clear();
    _marksAfter.clear();
    final sent = [
      for (final (position, row) in rows.indexed)
        if (row.shown case UserMessageItem(:final sentAt?)) (position, sentAt),
    ];
    for (final mark in widget.state.modelMarks(widget.desktopId, _sessionId)) {
      if (buffer.earlier == true &&
          (sent.isEmpty || mark.at.isBefore(sent.first.$2))) {
        continue;
      }
      final next = sent.where((entry) => entry.$2.isAfter(mark.at)).firstOrNull;
      if (next == null) {
        _marksAfter.add(mark.label);
      } else {
        (_marksBefore[next.$1 + 1] ??= []).add(mark.label);
      }
    }
  }

  /// [child] with the model switches placed at its row (see
  /// [_placeModelMarks]), as the CLI's own「已切换模型为」lines look.
  Widget _withModelMarks(int position, Widget child, {required bool last}) {
    Widget mark(String label) => NoticeRow(
      item: NoticeItem(NoticeKind.command, 'Set model to $label'),
      zh: tr('中', 'en') == '中',
    );
    final before = _marksBefore[position] ?? const [];
    final after = last ? _marksAfter : const <String>[];
    if (before.isEmpty && after.isEmpty) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final label in before) mark(label),
        child,
        for (final label in after) mark(label),
      ],
    );
  }

  /// 最后一条下面垫一点空：滚到底时它和下面的输入栏、胶囊之间有个缝。
  /// 别的行不垫，行与行之间的间距不受影响。
  static const _tailGap = 10.0;
}
