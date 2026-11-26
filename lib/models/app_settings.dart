import 'package:flutter/material.dart';

class BotTtsConfig {
  const BotTtsConfig({
    this.voiceId,
    this.voiceLabel,
    this.narratorVoiceId,
    this.narratorVoiceLabel,
    this.autoRead = false,
  });

  factory BotTtsConfig.fromJson(Map<String, Object?> json) => BotTtsConfig(
    voiceId: json['voiceId'] as String?,
    voiceLabel: json['voiceLabel'] as String?,
    narratorVoiceId: json['narratorVoiceId'] as String?,
    narratorVoiceLabel: json['narratorVoiceLabel'] as String?,
    autoRead: json['autoRead'] == true,
  );

  final String? voiceId;
  final String? voiceLabel;
  final String? narratorVoiceId;
  final String? narratorVoiceLabel;
  final bool autoRead;

  BotTtsConfig copyWith({
    String? voiceId,
    String? voiceLabel,
    bool clearVoice = false,
    String? narratorVoiceId,
    String? narratorVoiceLabel,
    bool clearNarratorVoice = false,
    bool? autoRead,
  }) => BotTtsConfig(
    voiceId: clearVoice ? null : (voiceId ?? this.voiceId),
    voiceLabel: clearVoice ? null : (voiceLabel ?? this.voiceLabel),
    narratorVoiceId: clearNarratorVoice
        ? null
        : (narratorVoiceId ?? this.narratorVoiceId),
    narratorVoiceLabel: clearNarratorVoice
        ? null
        : (narratorVoiceLabel ?? this.narratorVoiceLabel),
    autoRead: autoRead ?? this.autoRead,
  );

  Map<String, Object?> toJson() => {
    if (voiceId != null) 'voiceId': voiceId,
    if (voiceLabel != null) 'voiceLabel': voiceLabel,
    if (narratorVoiceId != null) 'narratorVoiceId': narratorVoiceId,
    if (narratorVoiceLabel != null) 'narratorVoiceLabel': narratorVoiceLabel,
    if (autoRead) 'autoRead': true,
  };
}

class AppSettings {
  AppSettings();

  String language = 'system';
  ThemeMode themeMode = ThemeMode.system;

  /// [MobileAccent]'s name.
  String accent = 'amber';
  String? desktop;
  Map<String, String> lastProjectByDesktop = {};
  double textScale = 1.0;
  double codeFontSize = 14;

  /// `chat.agentLoadingStyle` and the like, by the desktop's keys.
  Map<String, Object?> loaders = {};

  /// What the phone tells of, as the desktop's own notification settings:
  /// an agent waiting on you, an agent done, a bot's message.
  bool notifyNeedsInput = true, notifyDone = true, notifyBots = true;

  /// Any of them; setting it sets all three.
  bool get notifications => notifyNeedsInput || notifyDone || notifyBots;
  set notifications(bool value) =>
      notifyNeedsInput = notifyDone = notifyBots = value;

  /// The system was asked once to let the app notify; not again unasked.
  bool notificationsAsked = false;
  bool haptics = true;

  /// 状态栏胶囊 / 灵动岛：只在等你处理、运行中、完成未读时出现。
  bool liveActivity = true;

  /// Keeps an agent's changes as each of its turns ends, for every
  /// conversation: the phone's own, sent as the desktop's Keep.
  bool autoKeep = false;

  /// The bots pinned on the lists, as (desktop, bot): the phone's own choice,
  /// the desktop keeps no pin for a bot.
  Set<(String, String)> pinnedBots = {};
  Set<(String, String)> botsUnsuggesting = {};
  String ttsProvider = 'system';
  String? ttsCloudModel;
  double ttsRate = 1.0;
  double ttsPitch = 1.0;
  double ttsStability = 0.5;
  String? ttsMimoStyle;
  Map<(String, String), BotTtsConfig> botTts = {};
  String name = '';
  String gender = '';
  String signature = '';
  String? avatar;

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final settings = AppSettings();
    settings.language = switch (json['language']) {
      'zh' => 'zh',
      'en' => 'en',
      _ => 'system',
    };
    settings.themeMode =
        ThemeMode.values.asNameMap()[json['theme']] ?? ThemeMode.system;
    // 默认黑金（琥珀）；旧版本默认的绿色只迁移一次，用户之后选的
    // 任何颜色都照常保留，可以换回绿色。
    settings.accent = json['accentColor'] as String? ?? 'amber';
    settings.desktop = json['desktop'] as String?;
    if (json['lastProjectByDesktop'] case final Map<dynamic, dynamic> projects) {
      settings.lastProjectByDesktop = {
        for (final entry in projects.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    }
    settings.textScale = ((json['textScale'] as num?)?.toDouble() ?? 1.0)
        .clamp(0.6, 1.4)
        .toDouble();
    settings.codeFontSize = ((json['codeFontSize'] as num?)?.toDouble() ?? 14)
        .clamp(10, 18)
        .toDouble();
    if (json['loaders'] case final Map<dynamic, dynamic> loaders) {
      settings.loaders = loaders.cast<String, Object?>();
    } else if (const {'dots': 'dots', 'ring': 'circle'}[json['loader']]
        case final style?) {
      settings.loaders = {'chat.agentLoadingStyle': style};
    }
    // One switch before: each kind starts as it was.
    final all = json['notifications'] != false;
    settings.notifyNeedsInput = json['notifyNeedsInput'] as bool? ?? all;
    settings.notifyDone = json['notifyDone'] as bool? ?? all;
    settings.notifyBots = json['notifyBots'] as bool? ?? all;
    settings.notificationsAsked = json['notificationsAsked'] == true;
    settings.haptics = json['haptics'] != false;
    settings.liveActivity = json['liveActivity'] != false;
    settings.autoKeep = json['autoKeepChanges'] == true;
    settings.pinnedBots = {
      for (final entry in (json['pinnedBots'] as List?) ?? const [])
        if (entry case [final String desktop, final String bot]) (desktop, bot),
    };
    settings.botsUnsuggesting = {
      for (final entry in (json['botsUnsuggesting'] as List?) ?? const [])
        if (entry case [final String desktop, final String bot]) (desktop, bot),
    };
    settings.ttsProvider = switch (json['ttsProvider']) {
      'elevenlabs' => 'elevenlabs',
      'mimo' => 'mimo',
      _ => 'system',
    };
    settings.ttsCloudModel = json['ttsCloudModel'] as String?;
    settings.ttsRate = ((json['ttsRate'] as num?)?.toDouble() ?? 1.0)
        .clamp(0.5, 2.0)
        .toDouble();
    settings.ttsPitch = ((json['ttsPitch'] as num?)?.toDouble() ?? 1.0)
        .clamp(0.5, 1.5)
        .toDouble();
    settings.ttsStability = ((json['ttsStability'] as num?)?.toDouble() ?? 0.5)
        .clamp(0.0, 1.0)
        .toDouble();
    settings.ttsMimoStyle = json['ttsMimoStyle'] as String?;
    if (json['botTts'] case final List<Object?> entries) {
      for (final entry in entries) {
        if (entry is Map &&
            entry['desktop'] is String &&
            entry['bot'] is String) {
          settings.botTts[(
            entry['desktop'] as String,
            entry['bot'] as String,
          )] = BotTtsConfig.fromJson(Map<String, Object?>.from(entry));
        }
      }
    }
    settings.name = json['name'] as String? ?? '';
    settings.gender = json['gender'] as String? ?? '';
    settings.signature = json['signature'] as String? ?? '';
    settings.avatar = json['avatar'] as String?;
    return settings;
  }

  Map<String, Object?> toJson() => {
    'language': language,
    'theme': themeMode.name,
    'accentColor': accent,
    'desktop': desktop,
    'lastProjectByDesktop': lastProjectByDesktop,
    'textScale': textScale,
    'codeFontSize': codeFontSize,
    'loaders': loaders,
    'notifyNeedsInput': notifyNeedsInput,
    'notifyDone': notifyDone,
    'notifyBots': notifyBots,
    'notificationsAsked': notificationsAsked,
    'haptics': haptics,
    'liveActivity': liveActivity,
    'autoKeepChanges': autoKeep,
    'pinnedBots': [
      for (final (desktop, bot) in pinnedBots) [desktop, bot],
    ],
    'botsUnsuggesting': [
      for (final (desktop, bot) in botsUnsuggesting) [desktop, bot],
    ],
    'ttsProvider': ttsProvider,
    'ttsCloudModel': ttsCloudModel,
    'ttsRate': ttsRate,
    'ttsPitch': ttsPitch,
    'ttsStability': ttsStability,
    if (ttsMimoStyle != null) 'ttsMimoStyle': ttsMimoStyle,
    'botTts': [
      for (final entry in botTts.entries)
        {
          'desktop': entry.key.$1,
          'bot': entry.key.$2,
          ...entry.value.toJson(),
        },
    ],
    'name': name,
    'gender': gender,
    'signature': signature,
    'avatar': avatar,
  };
}
