import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'agent_step.dart';

/// A message a subagent sent the agent (SendMessage): at the agent's side,
/// as a card under the subagent's name (what it was given to do), not as
/// the user's bubble. It cannot be edited.
///
/// Mobile adaptation: the phone's markdown renders [body] (its links open
/// files off the desktop); no fill, only the step cards' outline, so it
/// does not read as the user's own white bubble.
class AgentMessageCard extends StatelessWidget {
  const AgentMessageCard({
    super.key,
    required this.agent,
    required this.body,
    required this.strings,
  });

  /// The subagent: what it was given to do, else its id.
  final String agent;
  final Widget body;
  final AgentStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final faint = scheme.onSurfaceVariant.withValues(
      alpha: MobileTheme.asideAlpha,
    );
    return Semantics(
      container: true,
      label: strings.agentMessageSemantics(agent),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.reply_rounded, size: 16, color: faint),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    agent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: MobileType.secondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    '· ${strings.agentMessageSent}',
                    style: TextStyle(color: faint, fontSize: MobileType.aside),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            body,
          ],
        ),
      ),
    );
  }
}
