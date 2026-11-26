import 'package:flutter/services.dart';

/// 系统自带 TTS 引擎提供的单个离线音色。
class TtsVoice {
  const TtsVoice({required this.name, required this.locale});

  final String name;
  final String locale;
}

/// 封装 Android 原生 TextToSpeech 通道。
abstract final class TtsSpeaker {
  static const _channel = MethodChannel('local.baocode.mobile/platform');

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

  static Future<void> stop() async {
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
final _markdownMarks = RegExp(r'(^|\s)[#>*~`]+|[*_`]+');
final _multiSpace = RegExp(r'\s+');

/// 剥离 Bot XML 标签、代码块与 Markdown 符号，只保留适合朗读的自然语言。
String cleanTextForTts(String raw) {
  var text = raw.replaceAll(_botSuggestBlock, ' ');
  text = text.replaceAll(_botOpenOrCloseTag, ' ');
  text = text.replaceAll(_fencedCodeBlock, ' ');
  text = text.replaceAllMapped(_markdownLink, (m) => m[1] ?? '');
  text = text.replaceAll(_urlPattern, ' ');
  text = text.replaceAll(_markdownMarks, ' ');
  return text.replaceAll(_multiSpace, ' ').trim();
}
