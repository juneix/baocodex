part of 'bots_tab.dart';

class BotProfilePage extends StatelessWidget {
  const BotProfilePage({
    super.key,
    required this.state,
    required this.ref,
    this.fromChat = false,
  });
  final AppState state;
  final BotRef ref;

  /// Opened from its conversation: going to it is going back.
  final bool fromChat;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => _BotProfileView(
      state: state,
      fromChat: fromChat,
      ref:
          state.bots
              .where(
                (current) =>
                    current.desktopId == ref.desktopId &&
                    current.bot.id == ref.bot.id,
              )
              .firstOrNull ??
          ref,
    ),
  );
}

/// A bot's page: who it is, set right here, each change sent at once.
class _BotProfileView extends StatefulWidget {
  const _BotProfileView({
    required this.state,
    required this.ref,
    required this.fromChat,
  });
  final AppState state;
  final BotRef ref;
  final bool fromChat;
  @override
  State<_BotProfileView> createState() => _BotProfileViewState();
}

class _BotProfileViewState extends State<_BotProfileView> {
  /// The desktop's answer to the last save, until its state says newer.
  LinkBot? _saved;
  bool _saving = false;
  bool? _pendingChatOnly;
  Set<BotAbility>? _pendingAbilities;

  AppState get state => widget.state;
  LinkBot get bot => _saved ?? widget.ref.bot;

  @override
  void didUpdateWidget(covariant _BotProfileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_saving &&
        !identical(oldWidget.ref.bot, widget.ref.bot) &&
        jsonEncode(oldWidget.ref.bot.toJson()) !=
            jsonEncode(widget.ref.bot.toJson())) {
      _saved = null;
    }
  }

  void _hint(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  /// The desktop keeps a bot whole: each save sends all of it.
  Future<void> _save({
    String? gender,
    String? identity,
    String? style,
    Set<BotAbility>? abilities,
    bool? chatOnly,
  }) async {
    if (_saving) return;
    final current = bot;
    final desktopId = widget.ref.desktopId;
    if (!state.isOnline(desktopId)) {
      return _hint(state.tr('电脑不在线，未保存。', 'Desktop offline. Not saved.'));
    }
    final nextChatOnly = chatOnly ?? current.chatOnly;
    if (current.chatOnly &&
        !nextChatOnly &&
        (!await _confirmComputerTools(context, state) || !mounted)) {
      return;
    }
    setState(() {
      _saving = true;
      _pendingChatOnly = chatOnly;
      _pendingAbilities = abilities;
    });
    final saver = state.botProfileSaver(desktopId, bot: current);
    try {
      final saved = await saver.save({
        'name': current.name,
        'identity': identity ?? current.identity,
        'style': style ?? current.style,
        'signature': current.signature,
        'gender': gender ?? current.gender,
        'avatar': current.avatar,
        'abilities': [
          for (final ability in abilities ?? current.abilities) ability.name,
        ],
        // 电脑端已不看它，只原样带回，保持整份资料。
        'proactive': current.proactive.toJson(),
      }, chatOnly: nextChatOnly);
      if (mounted) setState(() => _saved = saved);
    } on BotModeUnconfirmed {
      if (!mounted) return;
      setState(() => _saved = saver.saved);
      _hint(
        state.tr(
          '电脑未确认所选模式，请核对实际模式。',
          'The desktop did not confirm the mode. Check the actual mode.',
        ),
      );
    } on Object catch (error) {
      if (mounted) _hint(botSaveFailureMessage(error, state.tr));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _pendingChatOnly = null;
          _pendingAbilities = null;
        });
      }
    }
  }

  Future<void> _editText(
    String title,
    String value,
    String note,
    void Function(String) save,
  ) async {
    final text = await openPage<String>(
      context,
      _LongTextPage(state: state, title: title, value: value, note: note),
    );
    if (text != null && text != value && mounted) save(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bot = this.bot;
    final chatOnly = _pendingChatOnly ?? bot.chatOnly;
    final abilities = _pendingAbilities ?? bot.abilities;
    final ref = BotRef(widget.ref.desktopId, bot);
    return Scaffold(
      appBar: AppBar(title: Text(state.tr('资料', 'Profile'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          InkWell(
            key: const ValueKey('bot-profile-header'),
            borderRadius: BorderRadius.circular(MobileSizes.radius),
            onTap: () =>
                openPage<void>(context, BotEditPage(state: state, ref: ref)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  BotAvatar(state: state, ref: ref, size: 72),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(bot.name, style: theme.textTheme.titleLarge),
                            if (bot.assistant)
                              MobileTag(state.tr('助理', 'Assistant')),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bot.signature.isEmpty
                              ? state.tr('个性签名', 'Signature')
                              : bot.signature,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: MobileTheme.hintStyleOf(
                            context,
                            color: bot.signature.isEmpty
                                ? theme.colorScheme.outline
                                : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          state.tr(
                            '在 ${state.desktopName(widget.ref.desktopId)} 上',
                            'On ${state.desktopName(widget.ref.desktopId)}',
                          ),
                          style: MobileTheme.hintStyleOf(context),
                        ),
                      ],
                    ),
                  ),
                  LucideIcon(
                    'chevron-right',
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: MobileSizes.wideButton,
            onPressed: () => _conversation(context),
            icon: const LucideIcon('message-circle', size: 20),
            label: Text(state.tr('发消息', 'Send message')),
          ),
          const SizedBox(height: 16),
          GroupCard(
            children: [
              Builder(
                builder: (anchor) => SettingsRow(
                  state.tr('性别', 'Gender'),
                  value: bot.gender.isEmpty
                      ? state.tr('未填', 'Not filled')
                      : bot.gender,
                  onTap: _saving
                      ? null
                      : () async {
                          final value = await _pickGender(
                            anchor,
                            state,
                            bot.gender,
                          );
                          if (value != null && value != bot.gender && mounted) {
                            await _save(gender: value);
                          }
                        },
                ),
              ),
              SettingsRow(
                state.tr('模型', 'Model'),
                value: bot.model ?? state.tr('默认', 'Default'),
                onTap: () => _pickModel(context),
              ),
            ],
          ),
          SectionLabel(state.tr('身份设定', 'Identity')),
          _TextCard(
            text: bot.identity,
            empty: state.tr('还没写', 'Not written yet'),
            onTap: _saving
                ? null
                : () => _editText(
                    state.tr('身份设定', 'Identity'),
                    bot.identity,
                    _identityNote(state),
                    (text) => _save(identity: text),
                  ),
          ),
          _Note(_identityNote(state)),
          SectionLabel(state.tr('说话风格', 'Conversation style')),
          _TextCard(
            text: bot.style,
            empty: state.tr('还没写', 'Not written yet'),
            onTap: _saving
                ? null
                : () => _editText(
                    state.tr('说话风格', 'Conversation style'),
                    bot.style,
                    _styleNote(state),
                    (text) => _save(style: text),
                  ),
          ),
          _Note(_styleNote(state)),
          SectionLabel(state.tr('干活方式', 'How it works')),
          GroupCard(
            children: [
              _ModeTile(
                state: state,
                value: chatOnly,
                onChanged: _saving ? null : (value) => _save(chatOnly: value),
              ),
            ],
          ),
          _Note(_modeNote(state)),
          SectionLabel(state.tr('能力', 'Abilities')),
          GroupCard(
            children: [
              for (final ability in BotAbility.values)
                _AbilityTile(
                  state: state,
                  ability: ability,
                  value: abilities.contains(ability),
                  onChanged: _saving
                      ? null
                      : (value) => _save(
                          abilities: value
                              ? {...abilities, ability}
                              : ({...abilities}..remove(ability)),
                        ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          GroupCard(
            children: [
              SettingsRow(
                state.tr('记忆', 'Memory'),
                icon: 'brain',
                onTap: () => openPage<void>(
                  context,
                  BotMemoryPage(state: state, ref: ref),
                ),
              ),
              SettingsRow(
                state.tr('删除聊天记录', 'Delete chat history'),
                icon: 'trash-2',
                color: theme.colorScheme.error,
                onTap: () => runUi(
                  context,
                  () => _clearBotChat(context, state, widget.ref),
                ),
              ),
              if (!bot.assistant)
                SettingsRow(
                  state.tr('删除 Bot', 'Delete bot'),
                  icon: 'user-x',
                  color: theme.colorScheme.error,
                  onTap: () => runUi(context, () async {
                    if (await _deleteBot(context, state, widget.ref) &&
                        context.mounted) {
                      Navigator.pop(context);
                    }
                  }),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _Note(_limitsNote(state)),
          ),
        ],
      ),
    );
  }

  Future<void> _conversation(BuildContext context) async {
    if (widget.fromChat) {
      Navigator.pop(context);
      return;
    }
    await openPage<void>(
      context,
      ChatPage(
        state: state,
        desktopId: widget.ref.desktopId,
        sessionId: bot.session ?? 'bot:${bot.id}',
        title: bot.name,
        botId: bot.id,
      ),
    );
  }

  /// 模型选项跟着 Bot 的会话走，选择期间订阅它，不必进聊天页。
  Future<void> _pickModel(BuildContext context) async {
    final desktopId = widget.ref.desktopId;
    final session = bot.session;
    if (!state.isOnline(desktopId)) {
      return _hint(
        state.tr(
          '电脑不在线，不能换模型。',
          'Desktop offline. The model cannot be changed.',
        ),
      );
    }
    if (session == null) {
      return _hint(
        state.tr(
          '先和它说句话，再换模型。',
          'Send it a message first, then change the model.',
        ),
      );
    }
    await runUi(context, () async {
      await state.openSession(desktopId, session);
      try {
        if (!context.mounted) return;
        await showBottomSheetSurface<void>(
          context,
          size: SheetSize.large,
          builder: (_) => ModelSettingsSheet(
            state: state,
            desktopId: desktopId,
            sessionId: session,
          ),
        );
      } finally {
        await state.closeSession(desktopId, session);
      }
    });
  }
}

/// A new bot, all of it; or an existing one's name, picture, gender and
/// signature (the rest is set on its page).
