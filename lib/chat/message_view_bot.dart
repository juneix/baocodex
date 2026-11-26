part of 'message_view.dart';

/// 新 agent 的临时 id 不是给人看的，还没标题时也不露出来。
String _agentTitle(AppState state, SessionSummary? session, String id) {
  if (session == null) return id;
  final title = session.title.trim();
  return title.isEmpty ? state.tr('新对话', 'New chat') : session.title;
}

/// 和 Bot 聊天的样子：头像、带尖角的气泡、图片自成一条。
extension _BotMessage on MessageView {
  Widget _botParts(BuildContext context, List<(String, String)> parts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (tag, text) in parts)
          if (tag == ChatCodec.botSuggestTag)
            // 推荐只给输入框的胶囊，不进对话正文。
            const SizedBox.shrink()
          else if (tag == ChatCodec.botCardTag)
            _BotAgentCard(
              state: state,
              desktopId: desktopId,
              bot: bot!,
              id: text,
              onOpen: onOpenSession,
            )
          else if (tag == ChatCodec.botNarrateTag)
            Padding(
              padding: botContentInsets.add(
                const EdgeInsets.symmetric(vertical: 4),
              ),
              child: _botPart(
                context,
                tag,
                ChatCodec.withoutVoiceCues(text),
              ),
            )
          else
            MessageView(
              state: state,
              desktopId: desktopId,
              item: AssistantTextItem(ChatCodec.withoutVoiceCues(text)),
              bot: bot,
              projectId: projectId,
              sessionId: sessionId,
              onOpenSession: onOpenSession,
            ),
      ],
    );
  }

  Widget _botBubble(BuildContext context, ChatItem value) {
    final user = value is UserMessageItem;
    final text = user
        ? ChatCodec.withoutBotEvents(messageBody(value.text, value.images))
        : (value as AssistantTextItem).text;
    final scheme = Theme.of(context).colorScheme;
    final color = user
        ? botUserBubbleColor(context)
        : scheme.surfaceContainerLow;
    final avatar = user
        ? LetterAvatar(
            state.settings.name.isEmpty ? '我' : state.settings.name,
            image: state.settings.avatar,
            size: 40,
          )
        : BotAvatar(state: state, ref: bot!, size: 40);
    final sticker = ChatCodec.sticker(text);
    final body = sticker != null
        ? StickerView(sticker)
        : user
        ? Text(
            text,
            style: MobileTheme.messageStyleOf(context)
                .copyWith(color: const Color(0xFF111111)),
          )
        // 气泡是白的，里面的代码块要用白底上的浅灰。
        : MobileTheme.reading(context, child: _prose(text));
    void press() => showBottomSheetPanel<void>(
      context,
      title: state.tr('消息操作', 'Message'),
      closeLabel: state.tr('关闭', 'Close'),
      size: SheetSize.small,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
        children: [
          ListTile(
            leading: const LucideIcon('copy', size: 20),
            title: Text(state.tr('复制', 'Copy')),
            onTap: () {
              Navigator.pop(sheetContext);
              _copy(context, text, images: user ? value.images : const []);
            },
          ),
          if (!user && sticker == null && text.trim().isNotEmpty) ...[
            ListTile(
              leading: const LucideIcon('bell-ring', size: 20),
              title: Text(state.tr('朗读', 'Read aloud')),
              onTap: () {
                Navigator.pop(sheetContext);
                TtsSpeaker.speakForBot(
                  state,
                  desktopId: desktopId,
                  botId: bot!.bot.id,
                  rawText: text,
                );
              },
            ),
            ListTile(
              leading: const LucideIcon('circle-pause', size: 20),
              title: Text(state.tr('停止朗读', 'Stop reading')),
              onTap: () {
                Navigator.pop(sheetContext);
                TtsSpeaker.stop();
              },
            ),
          ],
          if (sticker == null && text.trim().isNotEmpty)
            ListTile(
              leading: const LucideIcon('file-text', size: 20),
              title: Text(state.tr('选择文本', 'Select text')),
              onTap: () {
                Navigator.pop(sheetContext);
                showBottomSheetPanel<void>(
                  context,
                  title: state.tr('选择文本', 'Select text'),
                  closeLabel: state.tr('关闭', 'Close'),
                  size: SheetSize.medium,
                  builder: (_) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: SelectableText(
                      text,
                      style: MobileTheme.messageStyleOf(context),
                    ),
                  ),
                );
              },
            ),
          if (user && onEdit != null)
            ListTile(
              leading: const LucideIcon('pencil', size: 20),
              title: Text(state.tr('编辑重发', 'Edit')),
              onTap: () {
                Navigator.pop(sheetContext);
                onEdit!(value);
              },
            ),
        ],
      ),
    );
    final bubble = Flexible(
      child: GestureDetector(
        onLongPress: press,
        child: Container(
          key: ValueKey(user ? 'bot-user-bubble' : 'bot-answer-bubble'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectionContainer.disabled(child: body),
        ),
      ),
    );
    final tail = Transform.translate(
      offset: Offset(user ? -1 : 1, 0),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CustomPaint(
          size: const Size(6, 10),
          painter: _BubbleTail(color, user),
        ),
      ),
    );
    final words = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: user
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: user
            ? [
                const SizedBox(width: 44),
                bubble,
                tail,
                const SizedBox(width: 4),
                avatar,
              ]
            : [
                avatar,
                const SizedBox(width: 4),
                tail,
                bubble,
                const SizedBox(width: 44),
              ],
      ),
    );
    if (!user || value.images.isEmpty) return words;
    // 图片自成一条，不进气泡；只有图时也不留空气泡。
    return Column(
      children: [
        if (text.isNotEmpty) words,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ImageDeck(
                    key: const ValueKey('bot-user-images'),
                    images: value.images
                        .map(GalleryImage.fromAttachment)
                        .toList(),
                    tr: state.tr,
                    onLongPress: press,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              avatar,
            ],
          ),
        ),
      ],
    );
  }
}

/// Bot 发的对话卡片：标题、状态和项目，点开进那个对话。
class _BotAgentCard extends StatelessWidget {
  const _BotAgentCard({
    required this.state,
    required this.desktopId,
    required this.bot,
    required this.id,
    this.onOpen,
  });

  final AppState state;
  final String desktopId, id;
  final BotRef bot;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = state.sessions
        .where((ref) => ref.desktopId == desktopId && ref.session.id == id)
        .firstOrNull
        ?.session;
    final title = _agentTitle(state, session, id);
    final project = state.projects
        .where(
          (ref) =>
              ref.desktopId == desktopId && ref.project.id == session?.project,
        )
        .firstOrNull
        ?.project
        .name;
    final status = switch (session?.status) {
      LinkSessionStatus.running => state.tr('[运行中]', '[Running]'),
      LinkSessionStatus.needsInput => state.tr('[等你处理]', '[Needs you]'),
      _ => null,
    };
    final meta = MobileTheme.metaStyleOf(context);
    final card = Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('bot-agent-card'),
        onTap: onOpen == null ? null : () => onOpen!(id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: MobileTheme.messageStyleOf(context),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: meta,
                        children: [
                          if (status != null)
                            TextSpan(
                              text: '$status ',
                              style: TextStyle(
                                color: MobileTheme.statusColorsOf(context).info,
                              ),
                            ),
                          if (project != null) TextSpan(text: project),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  LetterAvatar(title, size: 40),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BotAvatar(state: state, ref: bot, size: 40),
          const SizedBox(width: 4),
          Transform.translate(
            offset: const Offset(1, 0),
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: CustomPaint(
                size: const Size(6, 10),
                painter: _BubbleTail(scheme.surfaceContainerLow, false),
              ),
            ),
          ),
          Expanded(child: card),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _BubbleTail extends CustomPainter {
  const _BubbleTail(this.color, this.right);
  final Color color;
  final bool right;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(right ? 0 : size.width, 0)
      ..lineTo(right ? size.width : 0, size.height / 2)
      ..lineTo(right ? 0 : size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubbleTail oldDelegate) =>
      color != oldDelegate.color || right != oldDelegate.right;
}
