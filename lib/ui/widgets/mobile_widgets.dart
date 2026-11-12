import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:bao_link/bao_link.dart' show LinkLimits;
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';

import '../../state/app_state.dart';
import 'lucide_icon.dart';
import '../../theme/app_theme.dart';
import '../../models/user_facing_error.dart';

/// Saves received media into the device gallery under [album], with a
/// snackbar for both outcomes. Saving needs no permission on Android 10+.
Future<void> saveImageToGallery(
  BuildContext context,
  Uint8List bytes, {
  String album = 'YCode',
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await Gal.putImageBytes(bytes, album: album);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          AppState.phrase(
            '已保存到相册（相册名：$album）',
            'Saved to the gallery ($album)',
          ),
        ),
      ),
    );
  } on Object {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          AppState.phrase('保存到相册没有成功。', 'Could not save to the gallery.'),
        ),
      ),
    );
  }
}

/// 从相册挑一张头像，连它报的类型一起带回；超过大小上限就用一句人话
/// 拒绝。用户取消返回 null。
Future<({Uint8List bytes, String type})?> pickAvatar(
  BuildContext context,
  AppState state,
) async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 640,
    maxHeight: 640,
    imageQuality: 85,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.length > LinkLimits.avatar) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.tr('头像不能超过 1 MB', 'Avatar must be at most 1 MB')),
        ),
      );
    }
    return null;
  }
  return (bytes: bytes, type: file.mimeType ?? 'image/jpeg');
}

Future<T?> openPage<T>(BuildContext context, Widget page) {
  // 否则返回时焦点回到聊天输入框，键盘会再弹出来；草稿和光标不受影响。
  FocusManager.instance.primaryFocus?.unfocus();
  return Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));
}

/// Runs [action] for a control. A failure shows [errorMessage]'s words, never
/// the exception's own text — pass `(e) => userMessage(state, e)`.
Future<void> runUi(
  BuildContext context,
  Future<void> Function() action, {
  String Function(Object error)? errorMessage,
}) async {
  try {
    await action();
  } on Object catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          errorMessage?.call(error) ??
              switch (error) {
                // 代码自己说好的话照原样显示，别的只说一句人话。
                UserFacingError(:final message) => message,
                _ => AppState.phrase(
                  '操作没有成功，请稍后重试。',
                  'That did not work. Try again in a moment.',
                ),
              },
        ),
      ),
    );
  }
}

/// [action] names the button by what it does; [destructive] turns it red.
Future<bool> confirmAction(
  BuildContext context,
  AppState state,
  String title,
  String detail, {
  String? action,
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(title),
          content: Text(detail),
          actions: dialogButtons([
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(state.tr('取消', 'Cancel')),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: colors.error,
                      foregroundColor: colors.onError,
                    )
                  : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(action ?? state.tr('确认', 'Confirm')),
            ),
          ]),
        );
      },
    ) ??
    false;

/// Asks before leaving a page whose edits are not saved: back, the system's
/// or the app bar's. A [Navigator.pop] of the page's own goes through.
class DiscardGuard extends StatelessWidget {
  const DiscardGuard({
    super.key,
    required this.state,
    required this.dirty,
    required this.child,
  });
  final AppState state;
  final bool dirty;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !dirty,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final discard = await confirmAction(
        context,
        state,
        state.tr('放弃修改？', 'Discard changes?'),
        state.tr(
          '改动还没有保存，返回后会丢失。',
          'Your changes are not saved and will be lost.',
        ),
        action: state.tr('放弃', 'Discard'),
        destructive: true,
      );
      if (discard && context.mounted) Navigator.of(context).pop();
    },
    child: child,
  );
}

Future<String?> askText(
  BuildContext context,
  AppState state,
  String title, {
  String value = '',
  int lines = 1,
  String? hint,
}) async {
  final controller = TextEditingController(text: value);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 12,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: dialogButtons([
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(state.tr('取消', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(state.tr('保存', 'Save')),
        ),
      ]),
    ),
  );
  // Let the dialog's route finish before disposing the editable state.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  return result;
}

class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.children});
  final List<Widget> children;

  /// 分割线从文字开始，不划到图标下面。
  double get _lineIndent =>
      children.any((row) => row is SettingsRow && row.icon != null)
      ? 16 + 22 + 12
      : 16;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(MobileSizes.radius),
    child: ColoredBox(
      // White on the gray page, as a messenger's settings groups are.
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      // Each row gets its own Material: ListTile paints background and ink on the
      // nearest Material ancestor, which the card's ColoredBox would otherwise hide.
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) Divider(height: 1, indent: _lineIndent),
            Material(type: MaterialType.transparency, child: children[index]),
          ],
        ],
      ),
    ),
  );
}

/// 分段切换里选中的滑块：比灰色轨道亮，白页面、白面板上也看得出选了哪个。
Color segmentThumbColor(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return Theme.of(context).brightness == Brightness.dark
      ? scheme.onSurface.withValues(alpha: .16)
      : scheme.surfaceContainerHigh;
}

/// 分段切换：灰色轨道里一块滑块，选中项加粗。
class SegmentBar<T> extends StatelessWidget {
  const SegmentBar({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(MobileSizes.radius),
      ),
      child: Row(
        children: [
          for (final value in values)
            Expanded(
              child: Semantics(
                selected: value == selected,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelected(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    constraints: const BoxConstraints(minHeight: 36),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(6),
                    decoration: value == selected
                        ? BoxDecoration(
                            color: segmentThumbColor(context),
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .08),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          )
                        : null,
                    child: Text(
                      label(value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: value == selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: value == selected
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.inset = 16, this.top = 20});
  final String text;
  final double inset;

  /// 上方的留白；紧跟弹层标题时可收紧。
  final double top;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(inset, top, inset, 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: MobileTheme.hintStyleOf(context)),
    ),
  );
}

/// 一行可点的文字资料：值就在行里，点开输入框改；空着写「未填」。
class EditableSettingsRow extends StatelessWidget {
  const EditableSettingsRow({
    super.key,
    required this.state,
    required this.controller,
    required this.title,
    required this.onChanged,
    this.enabled = true,
  });

  final AppState state;
  final TextEditingController controller;
  final String title;

  /// 改完（且真的变了）才叫，返回值先落到 [controller] 里。
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SettingsRow(
    title,
    value: controller.text.isEmpty
        ? state.tr('未填', 'Not filled')
        : controller.text,
    onTap: enabled
        ? () async {
            final value = await askText(
              context,
              state,
              title,
              value: controller.text,
            );
            final next = value?.trim();
            if (next == null || next.isEmpty || next == controller.text) {
              return;
            }
            controller.text = next;
            onChanged(next);
          }
        : null,
  );
}

/// 卡片下面的一行灰字，说明这块是干什么的。三处页面原来各写一份，
/// 间距不同；这里按「卡片下方」统一：左边和卡片对齐，上面留一点空。
class CardNote extends StatelessWidget {
  const CardNote(this.text, {super.key, this.inset = MobileSpace.md});
  final String text;

  /// 左边距；和所在卡片的左右内边距对齐。
  final double inset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(inset, MobileSpace.sm, inset, 0),
    child: Text(text, style: MobileTheme.hintStyleOf(context)),
  );
}

class SettingsRow extends StatelessWidget {
  const SettingsRow(
    this.title, {
    super.key,
    this.icon,
    this.value,
    this.onTap,
    this.trailing,
    this.subtitle,
    this.color,
  });
  final Color? color;
  final String title;
  final String? icon;
  final String? value;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyMedium!.copyWith(color: color);
    final valueStyle = theme.textTheme.bodyMedium!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final available =
            constraints.maxWidth -
            32 -
            (icon == null ? 0 : 34) -
            (trailing != null
                ? 0
                : onTap == null
                ? 0
                : 26);
        double widthOf(String text, TextStyle style) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final stacked =
            trailing == null &&
            value != null &&
            (value!.contains('\n') ||
                widthOf(title, labelStyle) + widthOf(value!, valueStyle) + 12 >
                    available);
        final label = Text(title, style: labelStyle);
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (value != null && trailing == null && !stacked)
              Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 12),
                  Text(value!, style: valueStyle),
                ],
              )
            else
              label,
            if (value != null && trailing == null && stacked) ...[
              const SizedBox(height: 4),
              SelectionArea(child: Text(value!, style: valueStyle)),
            ],
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: theme.textTheme.bodySmall),
            ],
          ],
        );
        return Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: MobileSizes.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      LucideIcon(
                        icon!,
                        size: 22,
                        color: color ?? theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: content),
                    if (trailing != null) ...[
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * .45,
                        ),
                        child: trailing!,
                      ),
                    ] else if (onTap != null) ...[
                      const SizedBox(width: 8),
                      LucideIcon(
                        'chevron-right',
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One choice of several: the chosen one carries a check.
class PickRow extends StatelessWidget {
  const PickRow(
    this.title, {
    super.key,
    required this.selected,
    required this.onTap,
    this.leading,
  });
  final String title;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: ListTile(
      leading: leading,
      title: Text(title),
      trailing: selected
          ? LucideIcon(
              'check',
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
      onTap: onTap,
    ),
  );
}

// The same bytes for the same base64, so MemoryImage hits the image cache
// instead of decoding (and blanking) again on every rebuild.
final _avatarBytes = <String, Uint8List?>{};

Uint8List? _decodedAvatar(String image) {
  if (_avatarBytes.containsKey(image)) return _avatarBytes[image];
  Uint8List? bytes;
  try {
    bytes = base64Decode(image);
  } on FormatException {
    // A corrupt cache falls back to an initial.
  }
  if (_avatarBytes.length >= 16) _avatarBytes.remove(_avatarBytes.keys.first);
  return _avatarBytes[image] = bytes;
}

/// 名字对应的头像底色：同一串名字总是同一个色调，一样叫法在哪儿都同色。
Color letterToneOf(String name) {
  // Quiet mid-tones under white letters: a screen of them stays calm.
  const palette = [
    Color(0xFF4F7FC1),
    Color(0xFF4E9A7A),
    Color(0xFFC17A45),
    Color(0xFF7F6DB8),
    Color(0xFFC8625A),
    Color(0xFF4A98A8),
  ];
  final index =
      name.runes.fold<int>(0, (sum, rune) => sum + rune) % palette.length;
  return palette[index];
}

class LetterAvatar extends StatelessWidget {
  const LetterAvatar(
    this.name, {
    super.key,
    this.size = MobileSizes.avatar,
    this.color,
    this.image,
    this.imageBytes,
    this.emoji,
  });
  final String name;
  final double size;
  final Color? color;
  final String? image;

  /// Already-decoded bytes, preferred over re-decoding [image] base64.
  final Uint8List? imageBytes;
  final String? emoji;
  @override
  Widget build(BuildContext context) {
    Widget? picture;
    if (imageBytes != null) {
      picture = Image.memory(
        imageBytes!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else if (image != null) {
      final bytes = _decodedAvatar(image!);
      if (bytes != null) {
        picture = Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      }
    }
    final tone = color ?? letterToneOf(name);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * MobileSizes.avatarCorner),
      child:
          picture ??
          Container(
            width: size,
            height: size,
            color: tone,
            alignment: Alignment.center,
            child: Text(
              emoji ??
                  (name.isEmpty ? '?' : String.fromCharCode(name.runes.first)),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.48,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
    );
  }
}

/// Beside a status that says it is connecting.
class ConnectingSpinner extends StatelessWidget {
  const ConnectingSpinner({super.key, this.size = 12, this.color});
  final double size;

  /// 不给就跟旁边的说明文字同一个灰；同步中给主题色，一眼看出在忙。
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CircularProgressIndicator(
      strokeWidth: 1.5,
      color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

/// 名字后面的小标签（如「助理」）：浅灰蓝底、深灰蓝字，跟名字分得开又不抢眼。
class MobileTag extends StatelessWidget {
  const MobileTag(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Color(dark ? 0xFF2E3447 : 0xFFDFE3EE),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall!
            .copyWith(color: Color(dark ? 0xFFAEB8D6 : 0xFF4B5A87)),
      ),
    );
  }
}

/// A conversation, project or bot in a list, as chat apps lay them out: the
/// avatar, its title with the time on the right, a line under it with any
/// status on the right, and a divider under the text.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.leading,
    required this.title,
    this.compact = false,
    this.titleBold = true,
    this.highlighted = false,
    this.divider = true,
    this.note,
    this.aside,
    this.subtitle,
    this.flags = const [],
    this.time,
    this.status,
    this.trailing,
    this.onTap,
  });

  /// [MobileSizes.avatar] square, or a small icon in a navigation row.
  final Widget leading;
  final String title;
  final bool compact;

  /// 列表里的对话和项目名不用加粗，和其他列表项区分开。
  final bool titleBold;

  /// 选中的对话：整行铺一层浅金色圆角矩形，和参考图一样。
  final bool highlighted;

  /// 行间分割线；侧栏的对话列表不要。
  final bool divider;

  /// A tag on the title's line, left of the time (such as “助理”).
  final String? note;

  /// Muted, left of [note] and the time: something such as a conversation's
  /// model. Not a tag — it reads as part of the line, not as a badge.
  final Widget? aside;
  final String? subtitle;

  /// Coloured before [subtitle], such as “2 个运行中”.
  final List<(String, Color)> flags;
  final String? time;

  /// Under the time: running, pinned, unread.
  final Widget? status;

  /// After the text, such as an actions menu.
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    // 选中的对话：白底上叠一层主题色，不是把背景挖空。
    final selectedTint = MobileAccent.fillFor(
      theme.brightness,
      theme.colorScheme.primary,
    ).withValues(alpha: .55);
    final body = Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: highlighted
          ? BorderRadius.circular(MobileSizes.radius)
          : BorderRadius.zero,
      clipBehavior: highlighted ? Clip.antiAlias : Clip.none,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            // 先铺白底，再叠主题色；选中的行不会露出下面的灰色。
            if (highlighted)
              Positioned.fill(
                child: ColoredBox(color: selectedTint),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: compact ? 44 : MobileSizes.listRow,
                  ),
                  child: Padding(
                    // 选中行外面多套了 6 的内缩，这里减掉，内容左缘仍在同一条线上。
                    padding: EdgeInsets.symmetric(
                      horizontal: highlighted
                          ? MobileSpace.lg - 6
                          : MobileSpace.lg,
                      vertical: compact ? 8 : MobileSpace.md,
                    ),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: compact ? 22 : MobileSizes.avatar,
                          child: leading,
                        ),
                        SizedBox(width: compact ? 10 : MobileSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 右边的模型、标签和时间先排满，标题拿剩下的。
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: titleBold
                                          ? text.bodyMedium!.copyWith(
                                              fontWeight: FontWeight.w500,
                                            )
                                          : text.bodyMedium,
                                      // 侧栏里选中的对话不再另加对勾或色块。
                                    ),
                                  ),
                                  if (aside != null) ...[
                                    const SizedBox(width: MobileSpace.sm),
                                    // 有上限：长名字也不会把标题挤没。
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: MediaQuery.textScalerOf(context)
                                            .scale(96),
                                      ),
                                      child: DefaultTextStyle(
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.labelSmall!,
                                        child: aside!,
                                      ),
                                    ),
                                  ],
                                  if (note != null) ...[
                                    const SizedBox(width: MobileSpace.sm),
                                    MobileTag(note!),
                                  ],
                                  if (time != null) ...[
                                    const SizedBox(width: MobileSpace.sm),
                                    // 固定宽度：各行的相对时间右缘对齐。
                                    SizedBox(
                                      width: MediaQuery.textScalerOf(context)
                                          .scale(MobileSizes.timeColumn),
                                      child: Text(
                                        time!,
                                        textAlign: TextAlign.end,
                                        maxLines: 1,
                                        overflow: TextOverflow.clip,
                                        softWrap: false,
                                        style: text.labelSmall,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (subtitle != null ||
                                  flags.isNotEmpty ||
                                  status != null) ...[
                                const SizedBox(height: MobileSpace.xs),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text.rich(
                                        TextSpan(
                                          children: [
                                            for (final (i, (label, color))
                                                in flags.indexed) ...[
                                              if (i > 0)
                                                const TextSpan(text: ' · '),
                                              TextSpan(
                                                text: label,
                                                style: TextStyle(color: color),
                                              ),
                                            ],
                                            if (subtitle != null) ...[
                                              if (flags.isNotEmpty)
                                                const TextSpan(text: ' · '),
                                              TextSpan(text: subtitle),
                                            ],
                                          ],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.bodySmall,
                                      ),
                                    ),
                                    if (status != null) ...[
                                      const SizedBox(width: MobileSpace.sm),
                                      IconTheme.merge(
                                        data: IconThemeData(
                                          size: 16,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                        child: status!,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        ?trailing,
                      ],
                    ),
                  ),
                ),
                if (divider)
                  const Divider(height: 1, indent: MobileSizes.listIndent),
              ],
            ),
          ],
        ),
      ),
    );
    return highlighted
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: body,
          )
        : body;
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel(
    this.text, {
    super.key,
    this.icon = Icons.chat_bubble_outline,
    this.actionLabel,
    this.onAction,
  });
  final String text;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: Theme.of(context).hintColor),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

class SearchCapsule extends StatelessWidget {
  const SearchCapsule({
    super.key,
    required this.state,
    required this.onChanged,
    this.hint,
    this.controller,
    this.outlined = false,
  });
  final AppState state;
  final ValueChanged<String> onChanged;
  final String? hint;
  final TextEditingController? controller;

  /// 侧栏里给搜索框一圈圆角矩形的描边。
  final bool outlined;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: hint ?? state.tr('搜索', 'Search'),
            isDense: true,
            prefixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            prefixIcon: Padding(
              // 图标到文字的间距：12 的左边距 + 6 的图标后留白。
              padding: const EdgeInsets.only(left: 12, right: 6),
              child: LucideIcon(
                'search',
                size: 16,
                color: Theme.of(context).hintColor,
              ),
            ),
            constraints: const BoxConstraints(minHeight: 36),
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            border: outlined
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MobileSizes.radius),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  )
                : null,
            enabledBorder: outlined
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MobileSizes.radius),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
