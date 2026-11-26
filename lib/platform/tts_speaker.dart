import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../state/app_state.dart';

/// 语音朗读音色条目（本地系统音色或云端音色）。
class TtsVoice {
  const TtsVoice({
    required this.name,
    required this.locale,
    this.id,
    this.description,
  });

  /// 展示名称（系统音色即其唯一名；云端音色为可读名称）。
  final String name;
  final String locale;

  /// 云端音色 ID；系统音色为 null（直接用 [name]）。
  final String? id;
  final String? description;

  String get effectiveId => id ?? name;
}

/// 一条待朗读的片段：区分旁白（`<bot_narrate>`）与角色对白。
class TtsSegment {
  const TtsSegment({required this.isNarrator, required this.text});

  final bool isNarrator;
  final String text;
}

/// 封装系统原生 TextToSpeech 与通用云端 TTS（ElevenLabs / 小米 MiMo）。
abstract final class TtsSpeaker {
  static const _channel = MethodChannel('local.baocode.mobile/platform');
  static const _timeout = Duration(seconds: 20);
  static int _playEpoch = 0;

  static const elevenLabsModels = [
    ('eleven_multilingual_v2', 'Eleven Multilingual v2'),
    ('eleven_flash_v2_5', 'Eleven Flash v2.5'),
    ('eleven_turbo_v2_5', 'Eleven Turbo v2.5'),
  ];

  static const mimoModels = [
    ('mimo-v2.5-tts', 'MiMo V2.5 TTS'),
  ];

  static const mimoPresetVoices = [
    TtsVoice(
      name: 'MiMo 默认',
      id: 'mimo_default',
      locale: 'zh-CN / en-US',
      description: '跟随集群默认女声（冰糖 / Mia）',
    ),
    TtsVoice(
      name: 'Chloe',
      id: 'Chloe',
      locale: 'en-US',
      description: '英文女声',
    ),
    TtsVoice(
      name: 'Milo',
      id: 'Milo',
      locale: 'en-US',
      description: '英文男声',
    ),
    TtsVoice(
      name: 'Dean',
      id: 'Dean',
      locale: 'en-US',
      description: '英文男声',
    ),
  ];

  /// 按当前全局服务商试听指定音色。
  static Future<bool> previewForState(
    AppState state,
    String rawText, {
    required String voiceId,
  }) {
    final epoch = ++_playEpoch;
    return _speakSegment(
      state,
      rawText,
      provider: state.settings.ttsProvider,
      voiceId: voiceId,
      epoch: epoch,
    );
  }

  /// 按指定 Bot 的角色/旁白音色配置分角色队列朗读。
  static Future<bool> speakForBot(
    AppState state, {
    required String desktopId,
    required String botId,
    required String rawText,
  }) async {
    final epoch = ++_playEpoch;
    final provider = state.settings.ttsProvider;
    final config = state.botTtsConfig(desktopId, botId);
    final segments = splitBotTtsSegments(rawText);
    if (segments.isEmpty) return false;
    var playedAny = false;
    for (final segment in segments) {
      if (_playEpoch != epoch) return playedAny;
      final voiceId = segment.isNarrator
          ? (config.narratorVoiceId ?? config.voiceId)
          : config.voiceId;
      final ok = await _speakSegment(
        state,
        segment.text,
        provider: provider,
        voiceId: voiceId,
        epoch: epoch,
      );
      if (!ok) return playedAny;
      playedAny = true;
    }
    return playedAny;
  }

  /// 按当前全局配置拉取可用音色列表。
  static Future<List<TtsVoice>> availableVoices(AppState state) async {
    final provider = state.settings.ttsProvider;
    if (provider == 'system') return voices();
    if (provider == 'mimo') return mimoPresetVoices;
    final key = await state.ttsApiKey(provider);
    if (key == null || key.trim().isEmpty) return const [];
    return fetchElevenLabsVoices(key);
  }

  static Future<bool> _speakSegment(
    AppState state,
    String rawText, {
    required String provider,
    required String? voiceId,
    required int epoch,
  }) async {
    if (_playEpoch != epoch) return false;
    final settings = state.settings;
    if (provider == 'system') {
      return speak(
        rawText,
        voice: voiceId,
        rate: settings.ttsRate,
      );
    }
    final text = cleanTextForTts(rawText);
    if (text.isEmpty) return false;
    final apiKey = await state.ttsApiKey(provider);
    if (_playEpoch != epoch) return false;
    if (apiKey == null || apiKey.trim().isEmpty) return false;
    if (provider == 'elevenlabs') {
      if (voiceId == null || voiceId.isEmpty) return false;
      final modelId = settings.ttsCloudModel ?? elevenLabsModels.first.$1;
      final bytes = await synthesizeElevenLabs(
        apiKey: apiKey,
        voiceId: voiceId,
        modelId: modelId,
        text: text,
      );
      if (_playEpoch != epoch) return false;
      return playAudio(bytes, ext: 'mp3');
    }
    if (provider == 'mimo') {
      final effectiveVoice = voiceId ?? 'mimo_default';
      final modelId = settings.ttsCloudModel ?? mimoModels.first.$1;
      final bytes = await synthesizeMimo(
        apiKey: apiKey,
        voiceId: effectiveVoice,
        modelId: modelId,
        text: text,
      );
      if (_playEpoch != epoch) return false;
      return playAudio(bytes, ext: 'wav');
    }
    return false;
  }

  static Future<bool> speak(
    String rawText, {
    String? voice,
    double rate = 1.0,
  }) async {
    final text = cleanTextForTts(rawText);
    if (text.isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('ttsSpeak', {
        'text': text,
        'voice': voice,
        'rate': rate.clamp(0.5, 2.0).toDouble(),
      });
      return ok == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> playAudio(Uint8List bytes, {String ext = 'mp3'}) async {
    if (bytes.isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('ttsPlayAudio', {
        'bytes': bytes,
        'ext': ext,
      });
      return ok == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> stop() async {
    _playEpoch++;
    try {
      await _channel.invokeMethod<void>('ttsStop');
    } on MissingPluginException {
      // 测试环境无原生宿主时忽略。
    } on PlatformException {
      // 忽略停止异常。
    }
  }

  static Future<List<TtsVoice>> voices() async {
    try {
      final raw = await _channel.invokeListMethod<Object?>('ttsVoices');
      if (raw == null) return const [];
      return [
        for (final entry in raw)
          if (entry case {
            'name': final String name,
            'locale': final String locale,
          } when name.isNotEmpty)
            TtsVoice(name: name, locale: locale),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  static Future<List<TtsVoice>> fetchElevenLabsVoices(String apiKey) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client
          .getUrl(Uri.parse('https://api.elevenlabs.io/v1/voices'))
          .timeout(_timeout);
      request.headers.set('xi-api-key', apiKey.trim());
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('ElevenLabs ${response.statusCode}: $body');
      }
      return parseElevenLabsVoices(body);
    } finally {
      client.close(force: true);
    }
  }

  static List<TtsVoice> parseElevenLabsVoices(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) return const [];
    final list = decoded['voices'];
    if (list is! List) return const [];
    final result = <TtsVoice>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final id = entry['voice_id'];
      final name = entry['name'];
      if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
        continue;
      }
      final labels = entry['labels'];
      final tags = <String>[];
      if (labels is Map) {
        for (final key in ['accent', 'gender', 'age', 'use_case']) {
          final v = labels[key];
          if (v is String && v.trim().isNotEmpty) tags.add(v.trim());
        }
      }
      result.add(
        TtsVoice(
          name: name,
          id: id,
          locale: tags.isEmpty ? 'ElevenLabs' : tags.join(' · '),
        ),
      );
    }
    return result;
  }

  static Future<Uint8List> synthesizeElevenLabs({
    required String apiKey,
    required String voiceId,
    required String modelId,
    required String text,
  }) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client
          .postUrl(
            Uri.parse(
              'https://api.elevenlabs.io/v1/text-to-speech/${Uri.encodeComponent(voiceId)}',
            ),
          )
          .timeout(_timeout);
      request.headers.set('xi-api-key', apiKey.trim());
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'text': text,
          'model_id': modelId,
        }),
      );
      final response = await request.close().timeout(_timeout);
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_timeout)) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'ElevenLabs ${response.statusCode}: ${utf8.decode(bytes, allowMalformed: true)}',
        );
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Uint8List> synthesizeMimo({
    required String apiKey,
    required String voiceId,
    required String modelId,
    required String text,
  }) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client
          .postUrl(Uri.parse('https://api.xiaomimimo.com/v1/chat/completions'))
          .timeout(_timeout);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${apiKey.trim()}',
      );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'model': modelId,
          'messages': [
            {'role': 'assistant', 'content': text},
          ],
          'audio': {
            'format': 'wav',
            'voice': voiceId,
          },
        }),
      );
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join().timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('MiMo ${response.statusCode}: $body');
      }
      return parseMimoAudioResponse(body);
    } finally {
      client.close(force: true);
    }
  }

  static Uint8List parseMimoAudioResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('MiMo 响应格式无效');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('MiMo 响应缺少音频结果');
    }
    final first = choices.first;
    if (first is! Map) throw const FormatException('MiMo 响应条目无效');
    final message = first['message'];
    final audio = message is Map ? message['audio'] : null;
    final data = audio is Map ? audio['data'] : null;
    if (data is! String || data.isEmpty) {
      throw const FormatException('MiMo 响应缺少音频数据');
    }
    return base64Decode(data);
  }
}

final _botSuggestBlock = RegExp(
  r'<bot_suggest>.*?</bot_suggest>',
  dotAll: true,
);
final _botOpenOrCloseTag = RegExp(
  r'</?(?:bot_say|bot_narrate|bot_show_chat)(?:\s+[^>]*)?>',
);
final _fencedCodeBlock = RegExp(r'```[\s\S]*?```');
final _markdownLink = RegExp(r'\[([^\]]+)\]\([^\)]+\)');
final _urlPattern = RegExp(r'https?://\S+');
final _lineMarkdownMarks = RegExp(r'(^|\s)[#>*~`]+');
final _inlineMarkdownMarks = RegExp(r'[*_`]+');
final _multiSpace = RegExp(r'\s+');

final _botTagSegment = RegExp(
  r'<(bot_say|bot_narrate|bot_suggest|bot_show_chat)(?:\s+[^>]*)?>(.*?)</\1>',
  dotAll: true,
);

/// 按 `<bot_say>` 与 `<bot_narrate>` 顺序拆成可分角色朗读的片段。
List<TtsSegment> splitBotTtsSegments(String raw) {
  final segments = <TtsSegment>[];
  var cursor = 0;
  for (final match in _botTagSegment.allMatches(raw)) {
    if (match.start > cursor) {
      final plain = cleanTextForTts(raw.substring(cursor, match.start));
      if (plain.isNotEmpty) {
        segments.add(TtsSegment(isNarrator: false, text: plain));
      }
    }
    final tag = match[1];
    final body = match[2] ?? '';
    if (tag == 'bot_narrate') {
      final cleaned = cleanTextForTts(body);
      if (cleaned.isNotEmpty) {
        segments.add(TtsSegment(isNarrator: true, text: cleaned));
      }
    } else if (tag == 'bot_say') {
      final cleaned = cleanTextForTts(body);
      if (cleaned.isNotEmpty) {
        segments.add(TtsSegment(isNarrator: false, text: cleaned));
      }
    }
    cursor = match.end;
  }
  if (cursor < raw.length) {
    final tail = cleanTextForTts(raw.substring(cursor));
    if (tail.isNotEmpty) {
      segments.add(TtsSegment(isNarrator: false, text: tail));
    }
  }
  return segments;
}

/// 剥离 Bot XML 标签、代码块与 Markdown 符号，只保留适合朗读的自然语言。
String cleanTextForTts(String raw) {
  var text = raw.replaceAll(_botSuggestBlock, ' ');
  text = text.replaceAll(_botOpenOrCloseTag, ' ');
  text = text.replaceAll(_fencedCodeBlock, ' ');
  text = text.replaceAllMapped(_markdownLink, (m) => m[1] ?? '');
  text = text.replaceAll(_urlPattern, ' ');
  text = text.replaceAll(_lineMarkdownMarks, ' ');
  text = text.replaceAll(_inlineMarkdownMarks, '');
  return text.replaceAll(_multiSpace, ' ').trim();
}

String ttsProviderLabel(AppSettings settings, String Function(String, String) tr) =>
    switch (settings.ttsProvider) {
      'elevenlabs' => 'ElevenLabs',
      'mimo' => tr('小米 MiMo', 'Xiaomi MiMo'),
      _ => tr('系统本地', 'System'),
    };
