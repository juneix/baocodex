import 'package:baocode_mobile/models/app_settings.dart';
import 'package:baocode_mobile/platform/tts_speaker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('本地 TTS 文本清洗与配置', () {
    test('剥离 Bot 标签、代码块与 Markdown 符号', () {
      const raw = '''
<bot_narrate>她合上笔记本。</bot_narrate>
<bot_say>你好，这是**测试**链接：[点这里](https://example.com) 和 https://foo.bar</bot_say>
```dart
print('skip');
```
<bot_suggest>继续</bot_suggest>
''';
      final cleaned = cleanTextForTts(raw);
      expect(cleaned, '她合上笔记本。 你好，这是测试链接：点这里 和');
    });

    test('按 bot_narrate 与 bot_say 拆分角色与旁白片段', () {
      const raw = '''
<bot_narrate>她推开窗户。</bot_narrate>
<bot_say>早安！</bot_say>
<bot_suggest>继续</bot_suggest>
''';
      final segments = splitBotTtsSegments(raw);
      expect(segments, hasLength(2));
      expect(segments[0].isNarrator, isTrue);
      expect(segments[0].text, '她推开窗户。');
      expect(segments[1].isNarrator, isFalse);
      expect(segments[1].text, '早安！');
    });

    test('AppSettings 正确读写全局引擎配置与单 Bot TTS 配置', () {
      final settings = AppSettings()
        ..ttsProvider = 'mimo'
        ..ttsCloudModel = 'mimo-v2.5-tts'
        ..ttsRate = 1.5
        ..ttsPitch = 1.2
        ..ttsStability = 0.65
        ..ttsMimoStyle = '温柔一点'
        ..botTts[('d1', 'b1')] = const BotTtsConfig(
          voiceId: 'mimo_default',
          voiceLabel: 'MiMo 默认',
          narratorVoiceId: 'Chloe',
          narratorVoiceLabel: 'Chloe',
          autoRead: true,
        )
        ..botsUnsuggesting.add(('d1', 'b1'));

      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.ttsProvider, 'mimo');
      expect(restored.ttsCloudModel, 'mimo-v2.5-tts');
      expect(restored.ttsRate, 1.5);
      expect(restored.ttsPitch, 1.2);
      expect(restored.ttsStability, 0.65);
      expect(restored.ttsMimoStyle, '温柔一点');
      final botCfg = restored.botTts[('d1', 'b1')];
      expect(botCfg, isNotNull);
      expect(botCfg!.voiceId, 'mimo_default');
      expect(botCfg.voiceLabel, 'MiMo 默认');
      expect(botCfg.narratorVoiceId, 'Chloe');
      expect(botCfg.narratorVoiceLabel, 'Chloe');
      expect(botCfg.autoRead, isTrue);
      expect(restored.botsUnsuggesting, {('d1', 'b1')});
    });

    test('解析 ElevenLabs 音色列表与 MiMo 音频响应', () {
      final voices = TtsSpeaker.parseElevenLabsVoices(
        '{"voices":[{"voice_id":"v1","name":"Bella","description":"Warm voice","preview_url":"https://example.com/a.mp3","labels":{"accent":"american","gender":"female"}}]}',
      );
      expect(voices, hasLength(1));
      expect(voices.single.effectiveId, 'v1');
      expect(voices.single.name, 'Bella');
      expect(voices.single.locale, 'american · female');
      expect(voices.single.description, 'Warm voice');
      expect(voices.single.previewUrl, 'https://example.com/a.mp3');

      final audio = TtsSpeaker.parseMimoAudioResponse(
        '{"choices":[{"message":{"audio":{"data":"AAH/"}}}]}',
      );
      expect(audio, [0, 1, 255]);
    });

    test('AppSettings 限制语速在 0.5 到 2.0 之间', () {
      final low = AppSettings.fromJson({'ttsRate': 0.1});
      final high = AppSettings.fromJson({'ttsRate': 5.0});
      expect(low.ttsRate, 0.5);
      expect(high.ttsRate, 2.0);
    });
  });
}
