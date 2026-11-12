import 'package:flutter/material.dart';

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

  /// Keeps an agent's changes as each of its turns ends, for every
  /// conversation: the phone's own, sent as the desktop's Keep.
  bool autoKeep = false;

  /// The bots pinned on the lists, as (desktop, bot): the phone's own choice,
  /// the desktop keeps no pin for a bot.
  Set<(String, String)> pinnedBots = {};
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
    // 旧版本默认是绿色，存下来的 'green' 多半只是旧默认值；统一读成
    // 现在的黑金，避免升级后还是一片微信绿。
    final stored = json['accentColor'] as String?;
    settings.accent = stored == null || stored == 'green' ? 'amber' : stored;
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
    settings.autoKeep = json['autoKeepChanges'] == true;
    settings.pinnedBots = {
      for (final entry in (json['pinnedBots'] as List?) ?? const [])
        if (entry case [final String desktop, final String bot]) (desktop, bot),
    };
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
    'autoKeepChanges': autoKeep,
    'pinnedBots': [
      for (final (desktop, bot) in pinnedBots) [desktop, bot],
    ],
    'name': name,
    'gender': gender,
    'signature': signature,
    'avatar': avatar,
  };
}
