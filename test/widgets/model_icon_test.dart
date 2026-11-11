import 'dart:io';

import 'package:baocode_mobile/ui/widgets/model_icon.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// 和电脑端 `ModelBrand` 同一套认法。
void main() {
  test('模型名里认厂商，认不出是 null', () {
    expect(modelBrandOf('claude-sonnet-4-5'), 'claude');
    expect(modelBrandOf('deepseek-ai/DeepSeek-V3'), 'deepseek');
    expect(modelBrandOf('openai/gpt-5'), 'openai');
    expect(modelBrandOf('qwen3-max'), 'qwen');
    expect(modelBrandOf('meta-llama/Llama-4'), 'meta');
    expect(modelBrandOf('o3-mini'), 'openai');
    expect(modelBrandOf('my-private-tuning'), isNull);
  });

  test('列表里的短名字：logo 已经说了厂商和系列，名字里不再重复', () {
    // 电脑给了带空格的名字。
    expect(
      modelShortName('@p/deepseek-v4.1-flash', 'DeepSeek V4.1 Flash'),
      'V4.1 Flash',
    );
    expect(modelShortName('opus', 'Claude Opus 4.7'), 'Opus 4.7');
    // 名字就是 id（带不带上游前缀都一样）时从 id 拼。
    for (final (id, short) in [
      ('@provider-2/claude-opus-5-5', 'Opus 5.5'),
      ('@provider/deepseek-v4.1-flash', 'V4.1 Flash'),
      ('@provider/deepseek-v4-pro', 'V4 Pro'),
      ('gpt-6.1-sol', '6.1 Sol'),
      ('glm-5.3-flash', '5.3 Flash'),
      ('kimi-k3-1', 'K3.1'),
      ('minimax-m3', 'M3'),
      ('claude-sonnet-4-5-20250929', 'Sonnet 4.5'),
      ('o3-mini', 'O3 Mini'),
      ('my-tuning', 'My Tuning'),
    ]) {
      expect(modelShortName(id, id), short, reason: id);
      expect(modelShortName(id, splitModelId(id).model), short, reason: id);
    }
  });

  test('选项 id 拆成上游和模型', () {
    expect(splitModelId('@acme/deepseek-v3'), (
      provider: 'acme',
      model: 'deepseek-v3',
    ));
    // Claude Code 自己的模型没有上游前缀。
    expect(splitModelId('default'), (provider: '', model: 'default'));
    expect(splitModelId('@bad'), (provider: '', model: '@bad'));
  });

  testWidgets('CLI 自己的模型画 Claude 的 logo，认不出的画脑子', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            ModelIcon.ofId('default', provider: 'claude-code', size: 20),
            ModelIcon.ofId('@acme/mystery-model', size: 20),
          ],
        ),
      ),
    );
    final logos = tester
        .widgetList<SvgPicture>(find.byType(SvgPicture))
        .map((svg) => svg.bytesLoader)
        .whereType<SvgAssetLoader>()
        .map((loader) => loader.assetName)
        .toList();
    expect(logos, contains('assets/model_icons/claude.svg'));
    // 认不出的那个是 Lucide 的脑子，不是品牌 logo。
    expect(
      logos.where((name) => name.startsWith('assets/model_icons/')),
      hasLength(1),
    );
  });

  test('认不出模型时按上游的名字认厂商', () {
    expect(providerBrandOf('OpenRouter'), 'openrouter');
    expect(providerBrandOf('硅基流动'), 'siliconflow');
    expect(providerBrandOf('本地 Ollama'), 'ollama');
    expect(providerBrandOf('火山方舟'), 'volcengine');
    expect(providerBrandOf('provider-3'), isNull);
    expect(providerBrandOf('我的中转'), isNull);
  });

  testWidgets('模型名认不出时画上游的 logo', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ModelIcon.ofId(
          '@provider-3/mystery-model',
          providerLabel: 'OpenRouter',
          size: 20,
        ),
      ),
    );
    final loader =
        tester.widget<SvgPicture>(find.byType(SvgPicture)).bytesLoader
            as SvgAssetLoader;
    expect(loader.assetName, 'assets/model_icons/openrouter.svg');
  });

  test('每个可能画到的厂商都有 logo 文件', () {
    final source = File('lib/ui/widgets/model_icon.dart').readAsStringSync();
    final brands = {
      for (final match in RegExp(r"\), '([a-z]+)'\)").allMatches(source))
        match[1]!,
    };
    expect(brands, contains('openrouter'));
    for (final brand in brands) {
      expect(
        File('assets/model_icons/$brand.svg').existsSync(),
        isTrue,
        reason: '$brand 的 logo 没打包进来',
      );
    }
  });
}
