import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'lucide_icon.dart';

/// 模型和上游的 logo，全是一种颜色（电脑端 `assets/model_icons/` 的同一批
/// Simple Icons / Remix Icon），用周围的文字色画。
const _brandAssets = 'assets/model_icons';

/// Claude Code 自己的模型那一组在链路上的 id。
const _builtinProvider = 'claude-code';

/// [id] 里认出的厂商，和电脑端 `ModelBrand` 一样按名字认：`claude-sonnet-4-5`、
/// `deepseek-ai/DeepSeek-V3`、`openai/gpt-5`；认不出就是 null。
String? modelBrandOf(String id) {
  final name = id.toLowerCase();
  for (final (pattern, brand) in _models) {
    if (pattern.hasMatch(name)) return brand;
  }
  return null;
}

/// 列表里跟在 logo 后面的短名字：logo 已经说了是哪家，名字里就不再重复
/// 厂商和系列名：`DeepSeek V4.1 Flash` 是 `V4.1 Flash`，`gpt-6.1-sol` 是
/// `6.1 Sol`。[label] 是电脑给的名字；不是带空格的名字（电脑只给了 id 或
/// 拿 id 当名字）时从 id 拼：`@p/claude-opus-5-5` 是 `Opus 5.5`，日期后缀不要。
String modelShortName(String id, String label) {
  final named = label.trim().contains(RegExp(r'\s'));
  final source = named ? label.trim() : splitModelId(label).model;
  final brand = modelBrandOf(source) ?? modelBrandOf(splitModelId(id).model);
  var words = named
      ? source.split(RegExp(r'\s+'))
      : source
            .split('/')
            .last
            .replaceAll(RegExp(r'[-_]\d{8}$'), '')
            .split(RegExp(r'[-_\s]+'))
            .where((word) => word.isNotEmpty)
            .toList();
  // 开头那个词单独就认得出是这家（`claude`、`gpt`、`glm`），去掉；带数字
  // 的不算（`o3` 是型号）。
  if (words.length > 1 &&
      brand != null &&
      !RegExp(r'\d').hasMatch(words.first) &&
      modelBrandOf(words.first) == brand) {
    words = words.sublist(1);
  }
  if (named) return words.join(' ');
  // 相邻的纯数字是版本号的几段：`5-5` 是 `5.5`。
  final joined = <String>[];
  for (final word in words) {
    if (RegExp(r'^\d+$').hasMatch(word) &&
        joined.isNotEmpty &&
        RegExp(r'\d$').hasMatch(joined.last)) {
      joined.last = '${joined.last}.$word';
    } else {
      joined.add(word);
    }
  }
  return [
    for (final word in joined) '${word[0].toUpperCase()}${word.substring(1)}',
  ].join(' ');
}

/// 一个名字里的一截词：开头或分隔符之后。
RegExp _word(String pattern) =>
    RegExp('(^|[/_.: -])(?:$pattern)', caseSensitive: false);

final _models = [
  (_word('claude|anthropic'), 'claude'),
  (_word(r'gemini'), 'gemini'),
  (_word(r'gemma'), 'google'),
  (_word(r'deepseek'), 'deepseek'),
  (_word(r'qwen|qwq|qvq'), 'qwen'),
  (_word(r'glm|chatglm|codegeex|cogview|zhipu'), 'zhipu'),
  (_word(r'kimi|moonshot'), 'kimi'),
  (_word(r'minimax|abab'), 'minimax'),
  (_word(r'doubao'), 'doubao'),
  (_word(r'seed'), 'bytedance'),
  (_word(r'hunyuan'), 'hunyuan'),
  (_word(r'ernie|wenxin'), 'wenxin'),
  (_word(r'step-'), 'stepfun'),
  (_word(r'baichuan'), 'baichuan'),
  (_word(r'yi-'), 'yi'),
  (_word(r'grok|xai'), 'xai'),
  (
    _word(r'mistral|mixtral|codestral|devstral|magistral|ministral|pixtral'),
    'mistral',
  ),
  (_word(r'llama'), 'meta'),
  (_word(r'phi-'), 'microsoft'),
  (_word(r'nemotron|nvidia'), 'nvidia'),
  (_word(r'sonar|perplexity'), 'perplexity'),
  // 最后，因为最笼统：单独一个 `o3`，或 `o3-mini`。
  (_word(r'gpt|chatgpt|codex|openai|o\d+(?:$|[-_.: ])'), 'openai'),
];

/// 上游 [name]（它的 id 或名字）里认出的厂商 logo；认不出是 null。
/// 电脑端按上游的网址认，手机只收到 id 和名字，就按名字里的字认：
/// `OpenRouter`、`硅基流动`、`本地 Ollama`。
String? providerBrandOf(String name) {
  for (final (pattern, brand) in _providers) {
    if (pattern.hasMatch(name)) return brand;
  }
  return null;
}

RegExp _named(String pattern) => RegExp(pattern, caseSensitive: false);

final _providers = [
  (_named(r'openrouter'), 'openrouter'),
  (_named(r'silicon ?flow|硅基'), 'siliconflow'),
  (_named(r'together'), 'together'),
  (_named(r'fireworks'), 'fireworks'),
  (_named(r'hugging ?face'), 'huggingface'),
  (_named(r'ollama'), 'ollama'),
  (_named(r'lm ?studio'), 'lmstudio'),
  (_named(r'copilot'), 'githubcopilot'),
  (_named(r'azure'), 'azure'),
  (_named(r'bedrock|\baws\b|amazon'), 'bedrock'),
  (_named(r'cloudflare'), 'cloudflare'),
  (_named(r'vercel'), 'vercel'),
  (_named(r'vertex'), 'vertexai'),
  (_named(r'volc|火山|方舟'), 'volcengine'),
  (_named(r'doubao|豆包'), 'doubao'),
  (_named(r'anthropic'), 'anthropic'),
  (_named(r'claude'), 'claude'),
  (_named(r'openai|chatgpt'), 'openai'),
  (_named(r'gemini|google'), 'gemini'),
  (_named(r'deepseek|深度求索'), 'deepseek'),
  (_named(r'qwen|dashscope|通义|百炼|阿里'), 'qwen'),
  (_named(r'zhipu|bigmodel|智谱|\bz\.ai\b|\bglm'), 'zhipu'),
  (_named(r'moonshot|kimi|月之暗面'), 'moonshot'),
  (_named(r'minimax|海螺'), 'minimax'),
  (_named(r'hunyuan|混元|腾讯'), 'hunyuan'),
  (_named(r'wenxin|qianfan|文心|千帆|百度'), 'wenxin'),
  (_named(r'stepfun|阶跃'), 'stepfun'),
  (_named(r'baichuan|百川'), 'baichuan'),
  (_named(r'01\.ai|lingyi|零一'), 'yi'),
  (_named(r'\bx\.?ai\b|grok'), 'xai'),
  (_named(r'mistral'), 'mistral'),
  (_named(r'perplexity'), 'perplexity'),
  (_named(r'nvidia|英伟达'), 'nvidia'),
];

/// 选项 id 拆成上游和模型：`@provider/model`；不是这种写法的，整个就是模型。
({String provider, String model}) splitModelId(String id) {
  if (id.startsWith('@')) {
    final slash = id.indexOf('/');
    if (slash > 1 && slash < id.length - 1) {
      return (provider: id.substring(1, slash), model: id.substring(slash + 1));
    }
  }
  return (provider: '', model: id);
}

/// 模型 [model]（属于上游 [provider]，名字 [providerLabel]）的图标，和电脑端
/// `ModelIcon` 一样：名字里认得出的厂商 logo；认不出看上游，再认不出就一个脑子。
class ModelIcon extends StatelessWidget {
  const ModelIcon({
    super.key,
    required this.provider,
    required this.model,
    required this.size,
    this.providerLabel,
    this.color,
  });

  /// 从选项 id 画：`@上游/模型` 自带上游，上游没有时看 [provider]（它所在组的
  /// id，即选项目录里那个上游的 id）。
  ModelIcon.ofId(
    String id, {
    super.key,
    required this.size,
    this.color,
    String? provider,
    this.providerLabel,
  }) : model = splitModelId(id).model,
       provider = provider ?? splitModelId(id).provider;

  final String provider;
  final String model;
  final String? providerLabel;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final brand = provider == _builtinProvider
        ? 'claude'
        : modelBrandOf(model) ??
              providerBrandOf(providerLabel ?? '') ??
              providerBrandOf(provider);
    if (brand == null) return LucideIcon('brain', size: size, color: color);
    return SvgPicture.asset(
      '$_brandAssets/$brand.svg',
      width: size,
      height: size,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
    );
  }
}
