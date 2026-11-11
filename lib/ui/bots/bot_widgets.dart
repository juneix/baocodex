part of 'bots_tab.dart';

/// 对话首页与 Bot 页共用的长按菜单。助理不能删，只能删它的聊天。
class BotPressRow extends StatelessWidget {
  const BotPressRow({
    super.key,
    required this.state,
    required this.ref,
    required this.child,
  });
  final AppState state;
  final BotRef ref;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pinned = state.botPinned(ref);
    return PressMenuRow(
      items: [
        PressMenuItem(
          pinned ? state.tr('取消置顶', 'Unpin') : state.tr('置顶', 'Pin'),
          () => runUi(context, () => state.setBotPinned(ref, !pinned)),
        ),
        PressMenuItem(
          state.tr('Bot 资料', 'Bot profile'),
          () => openPage<void>(context, BotProfilePage(state: state, ref: ref)),
        ),
        if (state.isOnline(ref.desktopId))
          if (ref.bot.assistant)
            PressMenuItem(
              state.tr('删除该聊天', 'Delete chat'),
              () => runUi(context, () => _clearBotChat(context, state, ref)),
            )
          else
            PressMenuItem(
              state.tr('删除该 Bot', 'Delete bot'),
              () => runUi(context, () => _deleteBot(context, state, ref)),
            ),
      ],
      child: child,
    );
  }
}

Future<void> _clearBotChat(
  BuildContext context,
  AppState state,
  BotRef ref,
) async {
  if (!await confirmAction(
    context,
    state,
    state.tr('清空对话？', 'Clear conversation?'),
    state.tr(
      '删除 Bot 自己的历史对话，保留身份与记忆；不会停止或删除它派出的普通任务。',
      'Delete the bot conversation, keeping identity and memory. Delegated tasks are not stopped or deleted.',
    ),
    action: state.tr('清空', 'Clear'),
    destructive: true,
  )) {
    return;
  }
  await state.request(ref.desktopId, LinkMethods.clearBotChat, {
    'bot': ref.bot.id,
  });
}

/// Whether the bot was deleted.
Future<bool> _deleteBot(
  BuildContext context,
  AppState state,
  BotRef ref,
) async {
  if (!await confirmAction(
    context,
    state,
    state.tr('删除 Bot？', 'Delete bot?'),
    state.tr(
      '它的对话和记忆也会删除。',
      'Its conversation and memory will also be deleted.',
    ),
    action: state.tr('删除', 'Delete'),
    destructive: true,
  )) {
    return false;
  }
  await state.request(ref.desktopId, LinkMethods.deleteBot, {
    'bot': ref.bot.id,
  });
  await state.setBotPinned(ref, false);
  return true;
}

/// 最近说的一句，没聊过时是签名；身份设定是写给模型的，不露出来。
String? _botListLine(LinkBot bot) => switch (bot.last) {
  final last? when last.isNotEmpty => last,
  _ => bot.signature.isEmpty ? null : bot.signature,
};

class BotAvatar extends StatefulWidget {
  const BotAvatar({
    super.key,
    required this.state,
    required this.ref,
    this.size = MobileSizes.avatar,
    this.color,
  });
  final AppState state;
  final BotRef ref;
  final double size;
  final Color? color;
  @override
  State<BotAvatar> createState() => _BotAvatarState();
}

class _BotAvatarState extends State<BotAvatar> {
  static const _maxRetries = 4;

  Future<Uint8List?>? _picture;
  bool _online = false;
  int _retries = 0;
  Timer? _retry;

  void _load() {
    _retry?.cancel();
    _online = widget.state.isOnline(widget.ref.desktopId);
    final picture = widget.ref.bot.hasAvatarImage && _online
        ? widget.state.icons.get(
            widget.ref.desktopId,
            LinkMethods.botAvatar,
            widget.ref.bot.id,
            params: {'bot': widget.ref.bot.id},
            request: widget.state.request,
          )
        : null;
    _picture = picture;
    // 刚连上时请求可能失败；页面一直开着，不补取就一直是字母。
    picture?.then((bytes) {
      if (bytes != null ||
          !mounted ||
          !identical(_picture, picture) ||
          _retries >= _maxRetries) {
        return;
      }
      _retry = Timer(Duration(seconds: 2 << _retries++), () {
        if (mounted) setState(_load);
      });
    });
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BotAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 没连上时取不到，连上之后要补取，否则一直是字母。
    if (oldWidget.ref.bot.avatar != widget.ref.bot.avatar ||
        oldWidget.ref.desktopId != widget.ref.desktopId ||
        (!_online && widget.state.isOnline(widget.ref.desktopId))) {
      _retries = 0;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _picture,
    builder: (context, snapshot) => LetterAvatar(
      widget.ref.bot.name,
      size: widget.size,
      color: widget.color,
      imageBytes: snapshot.data,
      emoji: widget.ref.bot.hasAvatarImage ? null : widget.ref.bot.avatar,
    ),
  );
}

String _abilityIcon(BotAbility ability) => switch (ability) {
  BotAbility.agents => 'list-checks',
  BotAbility.browser => 'compass',
  BotAbility.proactive => 'bell-ring',
};

String _abilityTitle(AppState state, BotAbility ability) => switch (ability) {
  BotAbility.agents => state.tr('管智能体', 'Manage agents'),
  BotAbility.browser => state.tr('使用浏览器', 'Use the browser'),
  BotAbility.proactive => state.tr('接收智能体通知', 'Agent notifications'),
};

String _abilityDetail(AppState state, BotAbility ability) => switch (ability) {
  BotAbility.agents => state.tr(
    '查看、停止、重试、归档对话，代你发消息、新建对话',
    'View, stop, retry and archive chats; message and open chats for you',
  ),
  BotAbility.browser => state.tr(
    '像对话任务一样操作你的浏览器',
    'Drive your browser like a chat task',
  ),
  // The desktop's WATCH.md rules: some wake the model, some only notify
  // the phone or are only noted.
  BotAbility.proactive => state.tr(
    '对话在等你、出错，或它派的对话有进展时告诉它，由它决定要不要找你；它也能改成只记下，或直接通知你、不用模型。关掉后一条都不告诉它',
    'Hears when a chat waits, fails, or one it started moves on, and decides whether to reach you; it can also just note one, or notify you without using the model. Off, it hears nothing',
  ),
};

String _modeNote(AppState state) => state.tr(
  '关掉后它能读写文件、运行命令，在你们聊到的项目里自己动手，或派给 Agent；每轮会多带一万多 token 的工具说明。',
  'Off, it can read and write files and run commands in the projects you talk about, or hand work to an agent; each turn carries 10K+ tokens of tool descriptions.',
);

String _identityNote(AppState state) => state.tr(
  '它是谁、怎么说话、和你是什么关系，都由你来写。',
  'Who it is, how it talks, and your relationship — all up to you.',
);

String _styleNote(AppState state) => state.tr(
  '它的语气、口头禅、用不用表情。',
  'Its tone, catchphrases, whether it uses emoji.',
);

String _limitsNote(AppState state) => state.tr(
  '无论怎么设定，你认真问它时都会承认自己是 AI，不写露骨内容，提到伤害自己时会给出求助信息，也不能替你批准权限。',
  'No matter the setup, it will admit being an AI when asked seriously, never write explicit content, offer help if self-harm comes up, and never approve permissions for you.',
);

Future<bool> _confirmComputerTools(BuildContext context, AppState state) =>
    confirmAction(
      context,
      state,
      state.tr('允许 Bot 直接操作电脑？', 'Allow computer tools?'),
      state.tr(
        '电脑可向它提供命令和文件读写工具，运行方式由电脑决定。这与管理普通任务是不同权限；它不能替你批准其他任务。',
        'The desktop may provide command and file tools. This is separate from managing tasks and does not approve other agents for you.',
      ),
      action: state.tr('允许', 'Allow'),
    );

/// The app bar's compact action (at most 40 high), in the theme's color.
Widget _doneButton(AppState state, VoidCallback? onPressed) => Padding(
  padding: const EdgeInsets.only(right: 12),
  child: Center(
    child: FilledButton(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      child: Text(state.tr('完成', 'Done')),
    ),
  ),
);

/// Gray words under a card, saying what it is for.
class _Note extends CardNote {
  const _Note(super.text);
}

/// A white card one writes in, growing with what is written.
class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.fieldKey,
    required this.controller,
    required this.hint,
    this.minLines = 1,
    this.enabled = true,
    this.autofocus = false,
  });
  final Key fieldKey;
  final TextEditingController controller;
  final String hint;
  final int minLines;
  final bool enabled, autofocus;
  @override
  Widget build(BuildContext context) => GroupCard(
    children: [
      KeyedSubtree(
        key: fieldKey,
        child: TextField(
          controller: controller,
          enabled: enabled,
          autofocus: autofocus,
          minLines: minLines,
          maxLines: minLines > 10 ? minLines : 10,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: hint,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ),
    ],
  );
}

/// What a bot was written to be, shown as it reads; a tap edits it.
class _TextCard extends StatelessWidget {
  const _TextCard({required this.text, required this.empty, this.onTap});
  final String text, empty;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GroupCard(
      children: [
        InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: MobileSizes.control),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  text.isEmpty ? empty : text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: text.isEmpty
                        ? theme.colorScheme.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AbilityTile extends StatelessWidget {
  const _AbilityTile({
    required this.state,
    required this.ability,
    required this.value,
    required this.onChanged,
  });
  final AppState state;
  final BotAbility ability;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: ValueKey('bot-ability-${ability.name}'),
    secondary: LucideIcon(_abilityIcon(ability), size: 22),
    title: Text(_abilityTitle(state, ability)),
    subtitle: Text(_abilityDetail(state, ability)),
    value: value,
    onChanged: onChanged,
  );
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.state,
    required this.value,
    required this.onChanged,
  });
  final AppState state;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: const ValueKey('bot-chat-only'),
    secondary: const LucideIcon('message-circle', size: 22),
    title: Text(state.tr('只聊天', 'Chat only')),
    value: value,
    onChanged: onChanged,
  );
}

/// When a bot told of agents may write first: how often, and the hours
/// it keeps quiet.
/// 性别是选的，点开不弹键盘；以前手写的值留作一项，不会被改掉。
Future<String?> _pickGender(
  BuildContext anchor,
  AppState state,
  String current,
) {
  final options = {
    state.tr('男', 'Male'),
    state.tr('女', 'Female'),
    if (current.isNotEmpty) current,
  };
  return showMenuPanel<String>(anchor, [
    for (final value in options)
      MenuPanelItem(value, value, selected: value == current),
    MenuPanelItem('', state.tr('不填', 'Not filled'), selected: current.isEmpty),
  ], width: 160);
}

class _LongTextPage extends StatefulWidget {
  const _LongTextPage({
    required this.state,
    required this.title,
    required this.value,
    required this.note,
  });
  final AppState state;
  final String title, value, note;
  @override
  State<_LongTextPage> createState() => _LongTextPageState();
}

class _LongTextPageState extends State<_LongTextPage> {
  late final _text = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        _doneButton(
          widget.state,
          () => Navigator.pop(context, _text.text.trim()),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _InputCard(
          fieldKey: const ValueKey('bot-long-text'),
          controller: _text,
          hint: widget.state.tr('还没写', 'Not written yet'),
          minLines: 6,
          autofocus: true,
        ),
        _Note(widget.note),
      ],
    ),
  );
}
