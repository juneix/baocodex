import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../markdown/markdown_view.dart';

/// Assistant prose, as markdown.
class AssistantText extends StatelessWidget {
  const AssistantText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => MarkdownView(
    text,
    style: MobileTheme.messageStyleOf(context),
    options: MarkdownOptions(
      colors: Theme.of(context).colorScheme,
      inlineCodeStyle: MobileTheme.codeStyleOf(context),
      headingSizes: MobileTheme.headingSizesOf(context),
      gap: MobileTheme.markdownGap,
    ),
  );
}
