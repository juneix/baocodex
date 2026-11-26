import 'package:flutter/material.dart';

import '../../platform/tts_speaker.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../user_message.dart';
import '../widgets/bottom_sheet_panel.dart';
import '../widgets/lucide_icon.dart';
import 'settings_page.dart';

/// 全局「语音朗读 Beta」设置页：配置服务商、API Key、模型并试听音色。
class VoiceSettingsPage extends StatefulWidget {
  const VoiceSettingsPage({super.key, required this.state});
  final AppState state;

  @override
  State<VoiceSettingsPage> createState() => _VoiceSettingsPageState();
}

class _VoiceSettingsPageState extends State<VoiceSettingsPage> {
  String? _apiKey;
  bool _loadingVoices = false;
  List<TtsVoice> _voices = const [];

  AppState get state => widget.state;
  String get _provider => state.settings.ttsProvider;

  @override
  void initState() {
    super.initState();
    _loadProviderState();
  }

  Future<void> _loadProviderState() async {
    final provider = _provider;
    if (provider == 'system') {
      final local = await TtsSpeaker.voices();
      if (mounted) setState(() => _voices = local);
      return;
    }
    final key = await state.ttsApiKey(provider);
    if (!mounted) return;
    setState(() {
      _apiKey = key;
      _voices = provider == 'mimo' ? TtsSpeaker.mimoPresetVoices : const [];
    });
    if (provider == 'elevenlabs' && key != null && key.isNotEmpty) {
      await _refreshElevenLabsVoices(key);
    }
  }

  Future<void> _refreshElevenLabsVoices(String key) async {
    if (_loadingVoices) return;
    setState(() => _loadingVoices = true);
    try {
      final list = await TtsSpeaker.fetchElevenLabsVoices(key);
      if (mounted) setState(() => _voices = list);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMessage(state, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingVoices = false);
    }
  }

  String _maskedKey(String? key) {
    if (key == null || key.isEmpty) return state.tr('未填写', 'Not set');
    if (key.length <= 4) return '••••';
    return '•••• ${key.substring(key.length - 4)}';
  }

  Future<void> _pickProvider() async {
    final options = [
      ('system', state.tr('系统本地 TTS（离线免费）', 'System TTS (Offline)')),
      ('elevenlabs', 'ElevenLabs'),
      ('mimo', state.tr('小米 MiMo TTS', 'Xiaomi MiMo TTS')),
    ];
    await showBottomSheetPanel<void>(
      context,
      title: state.tr('服务商', 'Provider'),
      closeLabel: state.tr('关闭', 'Close'),
      size: SheetSize.small,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          for (final (id, label) in options)
            ListTile(
              title: Text(label),
              trailing: _provider == id
                  ? const LucideIcon('check', size: 18)
                  : null,
              onTap: () async {
                Navigator.pop(sheetContext);
                if (_provider == id) return;
                await state.setTtsSettings(
                  provider: id,
                  cloudModel: id == 'elevenlabs'
                      ? TtsSpeaker.elevenLabsModels.first.$1
                      : id == 'mimo'
                      ? TtsSpeaker.mimoModels.first.$1
                      : '',
                );
                await _loadProviderState();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _editApiKey() async {
    final provider = _provider;
    final controller = TextEditingController(text: _apiKey ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          provider == 'mimo'
              ? state.tr('小米 MiMo API Key', 'Xiaomi MiMo API Key')
              : 'ElevenLabs API Key',
        ),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            hintText: state.tr('粘贴 API Key（留空则清除）', 'Paste API key (empty to clear)'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(state.tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(state.tr('保存', 'Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null || !mounted) return;
    await state.setTtsApiKey(provider, saved);
    await _loadProviderState();
  }

  Future<void> _pickModel() async {
    final models = _provider == 'elevenlabs'
        ? TtsSpeaker.elevenLabsModels
        : TtsSpeaker.mimoModels;
    final current = state.settings.ttsCloudModel ?? models.first.$1;
    await showBottomSheetPanel<void>(
      context,
      title: state.tr('模型', 'Model'),
      closeLabel: state.tr('关闭', 'Close'),
      size: SheetSize.small,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          for (final (id, label) in models)
            ListTile(
              title: Text(label),
              subtitle: Text(id),
              trailing: current == id
                  ? const LucideIcon('check', size: 18)
                  : null,
              onTap: () async {
                Navigator.pop(sheetContext);
                await state.setTtsSettings(cloudModel: id);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickSystemRate() async {
    const rates = [0.75, 1.0, 1.25, 1.5, 1.75];
    await showBottomSheetPanel<void>(
      context,
      title: state.tr('朗读语速', 'Speech rate'),
      closeLabel: state.tr('关闭', 'Close'),
      size: SheetSize.small,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          for (final rate in rates)
            ListTile(
              title: Text('${rate.toStringAsFixed(2)}x'),
              trailing: (state.settings.ttsRate - rate).abs() < 0.01
                  ? const LucideIcon('check', size: 18)
                  : null,
              onTap: () async {
                Navigator.pop(sheetContext);
                await state.setTtsSettings(rate: rate);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _previewVoice(TtsVoice voice) async {
    await runUi(context, () async {
      final ok = await TtsSpeaker.previewForState(
        state,
        state.tr('你好，这是语音朗读测试。', 'Hello, this is a voice read-aloud test.'),
        voiceId: voice.effectiveId,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              state.tr(
                '无法试听，请检查引擎或 API Key 配置。',
                'Preview failed. Check the TTS engine or API key.',
              ),
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final settings = state.settings;
        final isSystem = settings.ttsProvider == 'system';
        final modelLabel = settings.ttsCloudModel ??
            (settings.ttsProvider == 'elevenlabs'
                ? TtsSpeaker.elevenLabsModels.first.$2
                : TtsSpeaker.mimoModels.first.$2);
        return Scaffold(
          appBar: AppBar(title: Text(state.tr('语音朗读 Beta', 'Voice read-aloud (Beta)'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              GroupCard(
                children: [
                  SettingsRow(
                    state.tr('服务商', 'Provider'),
                    value: ttsProviderLabel(settings, state.tr),
                    onTap: _pickProvider,
                  ),
                  if (!isSystem) ...[
                    SettingsRow(
                      'API Key',
                      value: _maskedKey(_apiKey),
                      onTap: _editApiKey,
                    ),
                    SettingsRow(
                      state.tr('模型', 'Model'),
                      value: modelLabel,
                      onTap: _pickModel,
                    ),
                  ],
                  if (isSystem)
                    SettingsRow(
                      state.tr('朗读语速', 'Speech rate'),
                      value: '${settings.ttsRate.toStringAsFixed(2)}x',
                      onTap: _pickSystemRate,
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                child: Text(
                  isSystem
                      ? state.tr(
                          '使用手机系统内置 TTS 引擎，无需网络或 API Key。可在各个 Bot 资料页中分别设置角色音色、旁白音色和自动朗读。',
                          'Uses the phone’s built-in TTS engine with no network or API key. Set character voice, narrator voice, and auto-read per bot.',
                        )
                      : settings.ttsProvider == 'elevenlabs'
                      ? state.tr(
                          '使用你自己的 ElevenLabs Key：朗读产生的费用记在你的账号上，Key 仅加密保存在本机。',
                          'Uses your own ElevenLabs key: usage is billed to your account and stored encrypted on this phone.',
                        )
                      : state.tr(
                          '使用你自己的小米 MiMo API Key（mimo-v2.5-tts）。Key 仅加密保存在本机。',
                          'Uses your own Xiaomi MiMo API key (mimo-v2.5-tts), stored encrypted on this phone.',
                        ),
                  style: MobileTheme.hintStyleOf(context),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SectionLabel(state.tr('音色试听', 'Voices')),
                  if (settings.ttsProvider == 'elevenlabs' &&
                      _apiKey != null &&
                      _apiKey!.isNotEmpty)
                    TextButton(
                      onPressed: _loadingVoices
                          ? null
                          : () => _refreshElevenLabsVoices(_apiKey!),
                      child: Text(
                        _loadingVoices
                            ? state.tr('拉取中…', 'Loading…')
                            : state.tr('刷新音色', 'Refresh'),
                      ),
                    ),
                ],
              ),
              GroupCard(
                children: [
                  if (_voices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        isSystem
                            ? state.tr(
                                '未获取到可用离线音色，将使用系统默认音色。',
                                'No offline voices reported; system default will be used.',
                              )
                            : state.tr(
                                '请先填写 API Key 后拉取或选择音色。',
                                'Enter your API key first to load voices.',
                              ),
                        style: MobileTheme.hintStyleOf(context),
                      ),
                    ),
                  for (final voice in _voices)
                    ListTile(
                      title: Text(voice.name),
                      subtitle: Text(
                        voice.description ?? voice.locale,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: state.tr('试听', 'Preview'),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        onPressed: () => _previewVoice(voice),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
