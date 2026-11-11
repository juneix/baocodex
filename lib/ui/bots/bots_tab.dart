import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../state/bot_settings.dart';
import '../devices/device_menu.dart';
import '../tasks/chat_page.dart';
import '../tasks/model_settings_sheet.dart';
import '../widgets/bottom_sheet_panel.dart';
import '../widgets/dropdown_panel.dart';
import '../widgets/lucide_icon.dart';
import '../widgets/mobile_widgets.dart';
import '../widgets/press_menu.dart';
import '../../theme/app_theme.dart';
import '../user_message.dart';
import '../widgets/fold_row.dart';

part 'bot_widgets.dart';
part 'bot_profile.dart';
part 'bot_edit.dart';
part 'bot_memory.dart';

class BotsTab extends StatelessWidget {
  const BotsTab({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final desktopId = state.selectedDesktopId;
    final mine = [
      for (final ref in state.bots)
        if (ref.desktopId == desktopId) ref,
    ];
    final bots = [
      ...mine.where(state.botPinned),
      ...mine.where((ref) => !state.botPinned(ref)),
    ];
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: DesktopSwitcherTitle(state: state),
        actions: [
          IconButton(
            icon: const LucideIcon('user-plus', size: 22),
            tooltip: state.tr('添加 Bot', 'Add bot'),
            onPressed: () => openPage<void>(context, BotEditPage(state: state)),
          ),
        ],
      ),
      body: state.desktops.isEmpty
          ? EmptyPanel(
              state.tr(
                '连接电脑后管理你的 Bot。',
                'Connect a desktop to manage your bots.',
              ),
            )
          : bots.isEmpty
          ? EmptyPanel(
              state.tr(
                '还没有 Bot。定义它是谁、能做什么。',
                'No bots yet. Define who one is and what it can do.',
              ),
              actionLabel: state.tr('添加 Bot', 'Add bot'),
              onAction: () =>
                  openPage<void>(context, BotEditPage(state: state)),
            )
          : ListView(
              children: [
                for (final ref in bots)
                  BotPressRow(
                    key: ValueKey('bot-${ref.desktopId}-${ref.bot.id}'),
                    state: state,
                    ref: ref,
                    child: ListRow(
                      leading: BotAvatar(state: state, ref: ref),
                      title: ref.bot.name,
                      note: ref.bot.assistant
                          ? state.tr('助理', 'Assistant')
                          : null,
                      subtitle: _botListLine(ref.bot),
                      status: state.botPinned(ref)
                          ? const LucideIcon('pin', size: 16)
                          : null,
                      onTap: () => openPage<void>(
                        context,
                        ChatPage(
                          state: state,
                          desktopId: ref.desktopId,
                          sessionId: ref.bot.session ?? 'bot:${ref.bot.id}',
                          title: ref.bot.name,
                          botId: ref.bot.id,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
