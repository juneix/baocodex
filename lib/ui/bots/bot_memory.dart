part of 'bots_tab.dart';

class BotMemoryPage extends StatefulWidget {
  const BotMemoryPage({super.key, required this.state, required this.ref});
  final AppState state;
  final BotRef ref;
  @override
  State<BotMemoryPage> createState() => _BotMemoryPageState();
}

class _BotMemoryPageState extends State<BotMemoryPage> {
  final _memory = TextEditingController(), _self = TextEditingController();
  BotMemorySaver? _memorySaver;

  /// What the desktop holds, as last loaded or saved.
  String _savedMemory = '', _savedSelf = '';
  bool get _dirty =>
      !_loading &&
      _error == null &&
      (_memory.text != _savedMemory || _self.text != _savedSelf);
  bool _loading = true, _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await widget.state.request(
        widget.ref.desktopId,
        LinkMethods.botMemory,
        {'bot': widget.ref.bot.id},
      );
      if (response is! Map ||
          response['text'] is! String ||
          response['self'] is! String) {
        throw const FormatException('电脑未返回有效记忆内容');
      }
      final result = Map<String, Object?>.from(response);
      if (!mounted) return;
      _memory.text = _savedMemory = result['text'] as String? ?? '';
      _self.text = _savedSelf = result['self'] as String? ?? '';
      _memory.addListener(_edited);
      _self.addListener(_edited);
      _memorySaver = BotMemorySaver(
        request: widget.state.request,
        desktopId: widget.ref.desktopId,
        botId: widget.ref.bot.id,
        memory: _memory.text,
        self: _self.text,
      );
    } on Object catch (error) {
      _error = userMessage(widget.state, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _memory.dispose();
    _self.dispose();
    super.dispose();
  }

  bool _wasDirty = false;
  void _edited() {
    if (_dirty != _wasDirty) setState(() => _wasDirty = _dirty);
  }

  Future<void> _save() async {
    if (_saving || _memorySaver == null) return;
    setState(() => _saving = true);
    try {
      final memory = _memory.text, self = _self.text;
      final result = await _memorySaver!.save(memory: memory, self: self);
      if (!mounted) return;
      if (result.saved.contains(LinkMethods.setBotMemory)) {
        _savedMemory = memory;
      }
      if (result.saved.contains(LinkMethods.setBotSelf)) _savedSelf = self;
      if (result.complete) {
        Navigator.pop(context);
      } else {
        final failures = [
          for (final entry in result.failed.entries)
            '${entry.key == LinkMethods.setBotMemory ? widget.state.tr('关于你', 'About you') : widget.state.tr('关于它自己', 'About itself')}: '
                '${botSaveFailureMessage(entry.value, widget.state.tr)}',
        ].join('\n');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.saved.isNotEmpty ? widget.state.tr('其他变更已保存。\n', 'Other changes were saved.\n') : ''}'
              '$failures\n${widget.state.tr('内容已保留，不会自动重试。', 'Content is kept; no automatic retry.')}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final name = widget.ref.bot.name;
    return DiscardGuard(
      state: state,
      dirty: _dirty && !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(state.tr('记忆', 'Memory')),
          actions: [
            TextButton(
              onPressed: _saving || _loading || _error != null ? null : _save,
              child: Text(state.tr('保存', 'Save')),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? EmptyPanel(
                _error!,
                actionLabel: state.tr('重试', 'Retry'),
                onAction: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  SectionLabel(state.tr('关于你', 'About you')),
                  _InputCard(
                    fieldKey: const ValueKey('bot-memory-user'),
                    controller: _memory,
                    hint: state.tr('还没有记下什么', 'Nothing noted yet'),
                    minLines: 5,
                    enabled: !_saving,
                  ),
                  _Note(
                    state.tr(
                      '$name 记下的关于你的事：称呼、习惯、在忙什么。聊天时它会自己补充，你也可以改。',
                      'What $name has noted of you: what to call you, your habits, what you are working on. It adds to this as you talk; you can edit it too.',
                    ),
                  ),
                  SectionLabel(state.tr('关于它自己', 'About itself')),
                  _InputCard(
                    fieldKey: const ValueKey('bot-memory-self'),
                    controller: _self,
                    hint: state.tr('还没有记下什么', 'Nothing noted yet'),
                    minLines: 5,
                    enabled: !_saving,
                  ),
                  _Note(
                    state.tr(
                      '$name 给自己记的：答应过你的事、做事的习惯。',
                      'What $name has noted of itself: what it promised you, how it works.',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _Note(
                      state.tr(
                        '只保存改过的一份。保存后它按新内容接着聊，聊天记录不受影响。',
                        'Only the one you changed is saved. It goes on from what is written; the chat is kept.',
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
