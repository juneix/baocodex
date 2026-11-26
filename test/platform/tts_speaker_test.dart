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

    test('AppSettings 正确读写本地 TTS 与推荐回复屏蔽配置', () {
      final settings = AppSettings()
        ..ttsAutoRead = true
        ..ttsVoice = 'zh-cn-x-afs-local'
        ..ttsRate = 1.5
        ..botsUnsuggesting.add(('d1', 'b1'));

      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.ttsAutoRead, isTrue);
      expect(restored.ttsVoice, 'zh-cn-x-afs-local');
      expect(restored.ttsRate, 1.5);
      expect(restored.botsUnsuggesting, {('d1', 'b1')});
    });

    test('AppSettings 限制语速在 0.5 到 2.0 之间', () {
      final low = AppSettings.fromJson({'ttsRate': 0.1});
      final high = AppSettings.fromJson({'ttsRate': 5.0});
      expect(low.ttsRate, 0.5);
      expect(high.ttsRate, 2.0);
    });
  });
}
