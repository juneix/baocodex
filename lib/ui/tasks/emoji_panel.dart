import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

const _emojis = [
  '😀',
  '😁',
  '😂',
  '🤣',
  '😊',
  '😇',
  '🙂',
  '😉',
  '😍',
  '🥰',
  '😘',
  '😋',
  '😜',
  '🤪',
  '😎',
  '🤩',
  '🥳',
  '😏',
  '😌',
  '😴',
  '🤔',
  '🤨',
  '😐',
  '😑',
  '🙄',
  '😬',
  '😮',
  '😯',
  '😲',
  '😳',
  '🥺',
  '😢',
  '😭',
  '😤',
  '😠',
  '😡',
  '🤯',
  '😅',
  '😆',
  '😝',
  '🤭',
  '🤗',
  '🤫',
  '😶',
  '🥱',
  '😷',
  '🤒',
  '🤕',
  '👍',
  '👎',
  '👌',
  '👏',
  '🙏',
  '💪',
  '🤝',
  '✌️',
  '❤️',
  '💔',
  '🔥',
  '🎉',
  '✨',
  '⭐',
  '✅',
  '❌',
];

/// 接在输入框下方的表情面板：点一下插入，删除和发送浮在右下角。
class EmojiPanel extends StatelessWidget {
  const EmojiPanel({
    super.key,
    required this.composer,
    required this.canSend,
    required this.onPick,
    required this.onDelete,
    required this.onSend,
    required this.deleteLabel,
    required this.sendLabel,
  });

  final TextEditingController composer;
  final bool Function() canSend;
  final ValueChanged<String> onPick;
  final VoidCallback onDelete, onSend;
  final String deleteLabel, sendLabel;

  static const _buttonSize = Size(56, MobileSizes.button);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = FilledButton.styleFrom(
      minimumSize: _buttonSize,
      maximumSize: _buttonSize,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    );
    return Stack(
      children: [
        GridView.builder(
          // 留出右下角按钮的高度，最后一行也点得到。
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 64),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
          ),
          itemCount: _emojis.length,
          itemBuilder: (context, index) => InkWell(
            key: ValueKey('emoji-$index'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => onPick(_emojis[index]),
            child: Center(
              child: Text(
                _emojis[index],
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
        ),
        Positioned(
          right: 4,
          bottom: 12,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: composer,
            builder: (context, value, _) => Row(
              children: [
                Tooltip(
                  message: deleteLabel,
                  child: FilledButton(
                    style: style.copyWith(
                      backgroundColor: WidgetStatePropertyAll(
                        scheme.surfaceContainerLowest,
                      ),
                      foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
                    ),
                    onPressed: value.text.isEmpty ? null : onDelete,
                    child: const Icon(Icons.backspace_outlined, size: 22),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('emoji-send'),
                  style: style,
                  onPressed: value.text.trim().isNotEmpty && canSend()
                      ? onSend
                      : null,
                  child: Text(sendLabel),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
