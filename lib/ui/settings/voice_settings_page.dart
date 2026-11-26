import 'package:flutter/material.dart';

import '../../platform/tts_speaker.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../user_message.dart';
import '../widgets/bottom_sheet_panel.dart';
import '../widgets/lucide_icon.dart';
import '../widgets/mobile_widgets.dart';

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
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => VoiceDetailPage(
                            state: state,
                            voice: voice,
                          ),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ValueListenableBuilder<TtsPlayState>(
                            valueListenable: TtsSpeaker.status,
                            builder: (context, playState, _) {
                              final active =
                                  playState.activeId == voice.effectiveId;
                              if (active &&
                                  playState.phase == TtsPlaybackPhase.loading) {
                                return IconButton(
                                  tooltip: state.tr('取消', 'Cancel'),
                                  icon: const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  onPressed: () => TtsSpeaker.stop(),
                                );
                              }
                              if (active &&
                                  playState.phase == TtsPlaybackPhase.playing) {
                                return IconButton(
                                  tooltip: state.tr('暂停', 'Pause'),
                                  icon: const Icon(
                                    Icons.pause_rounded,
                                    size: 20,
                                  ),
                                  onPressed: () => TtsSpeaker.stop(),
                                );
                              }
                              return IconButton(
                                tooltip: state.tr('试听', 'Preview'),
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 20,
                                ),
                                onPressed: () => _previewVoice(voice),
                              );
                            },
                          ),
                          const LucideIcon('chevron-right', size: 16),
                        ],
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

/// 单个音色的详情与微调页：支持官方免费样音、自定义试读文本、语速/稳定度或 MiMo 风格微调。
class VoiceDetailPage extends StatefulWidget {
  const VoiceDetailPage({
    super.key,
    required this.state,
    required this.voice,
  });

  final AppState state;
  final TtsVoice voice;

  @override
  State<VoiceDetailPage> createState() => _VoiceDetailPageState();
}

class _VoiceDetailPageState extends State<VoiceDetailPage> {
  late final TextEditingController _sampleText;
  late final TextEditingController _mimoStyle;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _sampleText = TextEditingController(
      text: state.tr(
        '你好呀，我在呢。今天想聊点什么？',
        'Hello there, I am here. What would you like to talk about today?',
      ),
    );
    _mimoStyle = TextEditingController(
      text: state.settings.ttsMimoStyle ?? '',
    );
  }

  @override
  void dispose() {
    _sampleText.dispose();
    _mimoStyle.dispose();
    super.dispose();
  }

  Future<void> _editSampleText() async {
    final controller = TextEditingController(text: _sampleText.text);
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(state.tr('试读文本', 'Sample text')),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(state.tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(state.tr('确定', 'OK')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updated != null && updated.trim().isNotEmpty && mounted) {
      setState(() => _sampleText.text = updated.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final voice = widget.voice;
    final sampleId = 'sample:${voice.effectiveId}';
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final provider = state.settings.ttsProvider;
        final isElevenLabs = provider == 'elevenlabs';
        final isMimo = provider == 'mimo';
        final rate = isElevenLabs
            ? state.settings.ttsRate.clamp(0.7, 1.2).toDouble()
            : state.settings.ttsRate.clamp(0.75, 1.75).toDouble();
        return Scaffold(
          appBar: AppBar(title: Text(voice.name)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(voice.locale, style: MobileTheme.hintStyleOf(context)),
                    if (voice.description != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        voice.description!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
              GroupCard(
                children: [
                  if (voice.previewUrl != null)
                    ValueListenableBuilder<TtsPlayState>(
                      valueListenable: TtsSpeaker.status,
                      builder: (context, playState, _) {
                        final active = playState.activeId == sampleId;
                        return ListTile(
                          title: Text(state.tr('播放样音', 'Play sample')),
                          trailing: active &&
                                  playState.phase == TtsPlaybackPhase.loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  active &&
                                          playState.phase ==
                                              TtsPlaybackPhase.playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 20,
                                ),
                          onTap: () {
                            if (active && playState.isActive) {
                              TtsSpeaker.stop();
                            } else {
                              runUi(
                                context,
                                () => TtsSpeaker.playSampleUrl(
                                  voice.previewUrl!,
                                  activeId: sampleId,
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  SettingsRow(
                    state.tr('试读文本', 'Sample text'),
                    value: _sampleText.text,
                    onTap: _editSampleText,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<TtsPlayState>(
                valueListenable: TtsSpeaker.status,
                builder: (context, playState, _) {
                  final active = playState.activeId == voice.effectiveId;
                  final loading =
                      active && playState.phase == TtsPlaybackPhase.loading;
                  final playing =
                      active && playState.phase == TtsPlaybackPhase.playing;
                  return FilledButton.icon(
                    style: MobileSizes.wideButton,
                    onPressed: () {
                      if (active && playState.isActive) {
                        TtsSpeaker.stop();
                      } else {
                        runUi(
                          context,
                          () => TtsSpeaker.previewForState(
                            state,
                            _sampleText.text,
                            voiceId: voice.effectiveId,
                          ),
                        );
                      }
                    },
                    icon: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.graphic_eq_rounded,
                            size: 20,
                          ),
                    label: Text(
                      loading
                          ? state.tr('生成中…', 'Generating…')
                          : playing
                          ? state.tr('停止试读', 'Stop')
                          : state.tr('试读', 'Test voice'),
                    ),
                  );
                },
              ),
              SectionLabel(state.tr('调节', 'Tuning')),
              GroupCard(
                children: [
                  if (!isMimo)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(state.tr('语速', 'Speed')),
                              Text('${rate.toStringAsFixed(2)}x'),
                            ],
                          ),
                          Slider(
                            value: rate,
                            min: isElevenLabs ? 0.7 : 0.75,
                            max: isElevenLabs ? 1.2 : 1.75,
                            divisions: isElevenLabs ? 5 : 4,
                            onChanged: (value) =>
                                state.setTtsSettings(rate: value),
                          ),
                        ],
                      ),
                    ),
                  if (!isElevenLabs && !isMimo)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(state.tr('音高', 'Pitch')),
                              Text(
                                '${state.settings.ttsPitch.toStringAsFixed(2)}x',
                              ),
                            ],
                          ),
                          Slider(
                            value: state.settings.ttsPitch.clamp(0.5, 1.5),
                            min: 0.5,
                            max: 1.5,
                            divisions: 10,
                            onChanged: (value) =>
                                state.setTtsSettings(pitch: value),
                          ),
                        ],
                      ),
                    ),
                  if (isElevenLabs)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(state.tr('稳定度', 'Stability')),
                              Text(
                                '${(state.settings.ttsStability * 100).round()}%',
                              ),
                            ],
                          ),
                          Slider(
                            value: state.settings.ttsStability,
                            min: 0.0,
                            max: 1.0,
                            divisions: 10,
                            onChanged: (value) =>
                                state.setTtsSettings(stability: value),
                          ),
                        ],
                      ),
                    ),
                  if (isMimo)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: _mimoStyle,
                        decoration: InputDecoration(
                          labelText: state.tr('风格指令（可选）', 'Style prompt (optional)'),
                          hintText: state.tr(
                            '例如：温柔一点，语速稍慢',
                            'e.g. Warm and slightly slower',
                          ),
                        ),
                        onSubmitted: (value) =>
                            state.setTtsSettings(mimoStyle: value),
                        onTapOutside: (_) =>
                            state.setTtsSettings(mimoStyle: _mimoStyle.text),
                      ),
                    ),
                ],
              ),
              if (isElevenLabs)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                  child: Text(
                    state.tr(
                      '稳定度越低越有感情，每次读得越不一样；越高越平稳。',
                      'Lower stability adds expressiveness; higher values keep delivery more consistent.',
                    ),
                    style: MobileTheme.hintStyleOf(context),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
