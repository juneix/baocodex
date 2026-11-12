import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

class _MobilePageTransitionsBuilder extends CupertinoPageTransitionsBuilder {
  const _MobilePageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 260);
}

/// 字号档位：全应用只用这几档，不在页面里写字号数字。
abstract final class MobileType {
  /// 对话框与大标题。
  static const headline = 18.0;

  /// 顶栏标题。
  static const title = 17.0;

  /// 正文：对话、列表标题、设置项、输入框、按钮。
  static const body = 16.0;

  /// 次要：副标题、说明、对话里的步骤行。
  static const secondary = 14.0;

  /// 等宽内容：命令、输出、差异、行内代码。
  static const mono = 13.0;

  /// 对话里的辅助说明：进度、统计、提示、差异计数。
  static const aside = 13.0;

  /// 元信息：时间、计数、角标。
  static const caption = 12.0;
}

/// 间距档位。
abstract final class MobileSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

/// 对话框底部的按钮：一行平分宽度、居中，和常见手机 App 一样。取消在左，
/// 确认在右；放进 [AlertDialog.actions]。
List<Widget> dialogButtons(List<Widget> buttons) => [
  Row(
    children: [
      for (final (index, button) in buttons.indexed) ...[
        if (index > 0) const SizedBox(width: 12),
        Expanded(child: button),
      ],
    ],
  ),
];

abstract final class MobileSizes {
  /// 列表头像：会话、项目、Bot 一致。
  static const avatar = 44.0;

  /// 双行列表行最小高度（头像上下各留 12）。
  static const listRow = 68.0;

  /// 列表分割线左缩进，对齐标题文字。
  static const listIndent = MobileSpace.lg + avatar + MobileSpace.md;

  /// 可点控件与单行条目最小高度。
  static const control = 48.0;

  /// 文字按钮看到的高度；点击区域仍是 [control]。
  static const button = 36.0;

  /// 页面底部占满整行的主要操作；其余按钮用主题默认的 [button] 高度。
  static const wideButton = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size.fromHeight(control)),
  );

  /// 分组、卡片与控件圆角。
  static const radius = 12.0;

  /// 消息气泡圆角（对话与字号预览共用）。
  static const bubbleRadius = 16.0;

  /// 头像圆角占边长的比例。
  static const avatarCorner = .24;
}

/// The app's color: buttons, links, the selected. Each has its tone for
/// light and dark; all but [amber] sit on plain gray, [amber] (the default,
/// 黑金 as the desktop) on its warm paper. Pale fills that carry black text
/// are [goldFill] / [goldInk], kept apart from the readable accent.
enum MobileAccent {
  green('绿色', 'Green', Color(0xFF07C160), Color(0xFF07B45A)),
  blue('蓝色', 'Blue', Color(0xFF1677FF), Color(0xFF4C8DF6)),
  graphite('石墨', 'Graphite', Color(0xFF262626), Color(0xFFE6E6E6)),
  indigo('靛紫', 'Indigo', Color(0xFF5856D6), Color(0xFF7D7AFF)),
  amber('琥珀', 'Amber', Color(0xFF966A25), Color(0xFFE4B16A));

  const MobileAccent(this.zh, this.en, this.light, this.dark);
  final String zh, en;
  final Color light, dark;

  Color of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 黑金按钮底：浅金，压黑字。桌面端同款；比主题色浅，才压得住黑字。
  static const goldFill = Color(0xFFF1CE7E);

  /// 黑金按钮上的字和图标。
  static const goldInk = Color(0xFF1A1A1A);

  /// The one a phone starts with: 黑金, as the desktop app.
  static const fallback = amber;

  static MobileAccent parse(Object? name) =>
      values.asNameMap()[name] ?? fallback;
}

/// The grays a theme is made of, beneath its accent, laid out as phone
/// messengers are: the page a light gray, what is on it (rows, groups,
/// sheets, fields, bubbles) white. [fill] is see-through, so what sits inside
/// either (inline code, a selected row) shows on both.
class _Neutrals {
  const _Neutrals({
    required this.page,
    required this.cell,
    required this.raised,
    required this.bar,
    required this.fill,
    required this.ink,
    required this.subtle,
    required this.line,
    required this.outline,
    required this.chip,
  });
  final Color page, cell, raised, bar, fill, ink, subtle, line, outline, chip;

  // WeChat's, measured off its screens: a #EDEDED page and top bar, #E5E5E5
  // lines, #191919 text; at night #111111 under #191919. Secondary text a
  // little darker than its #7F7F7F, to read on the gray page. Its pure white cells and #F7F7F7 bottom bar taken a step down,
  // pure white being too glaring here; the bar stays a step under the cells.
  static const plainLight = _Neutrals(
    page: Color(0xFFEDEDED),
    cell: Color(0xFFFAFAFA),
    raised: Color(0xFFFAFAFA),
    bar: Color(0xFFF3F3F3),
    fill: Color(0x12000000),
    ink: Color(0xFF191919),
    subtle: Color(0xFF6B6B6B),
    line: Color(0xFFE5E5E5),
    outline: Color(0xFFC7C7C7),
    chip: Color(0xFFEDEDED),
  );
  static const plainDark = _Neutrals(
    page: Color(0xFF111111),
    cell: Color(0xFF191919),
    raised: Color(0xFF2C2C2C),
    bar: Color(0xFF222222),
    fill: Color(0x14FFFFFF),
    ink: Color(0xFFE5E5E5),
    subtle: Color(0xFF808080),
    line: Color(0xFF2C2C2C),
    outline: Color(0xFF4A4A4A),
    chip: Color(0xFF2C2C2C),
  );
  static const warmLight = _Neutrals(
    page: Color(0xFFF2F2EE),
    cell: Color(0xFFFBFBF8),
    raised: Color(0xFFFBFBF8),
    bar: Color(0xFFF5F5F1),
    fill: Color(0x122E2E2A),
    ink: Color(0xFF2E2E2A),
    subtle: Color(0xFF686B63),
    line: Color(0xFFE7E8E1),
    outline: Color(0xFFC9CAC3),
    chip: Color(0xFFE2E3DB),
  );
  static const warmDark = _Neutrals(
    page: Color(0xFF1A1B18),
    cell: Color(0xFF242521),
    raised: Color(0xFF2E2F2A),
    bar: Color(0xFF2B2C27),
    fill: Color(0x14FFFFFF),
    ink: Color(0xFFE5E5DF),
    subtle: Color(0xFFAAACA3),
    line: Color(0xFF383A33),
    outline: Color(0xFF55574F),
    chip: Color(0xFF3A3B35),
  );
}

abstract final class MobileTheme {
  /// 底色是白的一块（文件预览、Bot 的白气泡）：页面换成白，顶栏随之；代码块随之
  /// 变浅灰，见 [codeSurfaceOf]。
  /// 代码块的底：灰底上是白卡片，白底上是浅灰。
  static Color codeSurfaceOf(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return colors.surface == colors.surfaceContainerLowest
        ? colors.surfaceBright
        : colors.surfaceContainerLowest;
  }

  static Widget reading(BuildContext context, {required Widget child}) {
    final theme = Theme.of(context);
    final white = theme.colorScheme.surfaceContainerLowest;
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(surface: white),
        scaffoldBackgroundColor: white,
        appBarTheme: theme.appBarTheme.copyWith(backgroundColor: white),
      ),
      child: child,
    );
  }

  /// Shell-command syntax colors, the terminal's ANSI yellow/magenta/cyan
  /// (desktop `AppColors.syntaxCommand…`): each light one is `ansi_text.dart`'s
  /// normal palette entry, its dark one the bright entry.
  static Color syntaxCommand(bool dark) =>
      Color(dark ? 0xffedcb68 : 0xff8a6300);
  static Color syntaxString(bool dark) => Color(dark ? 0xffdc8de2 : 0xff9235a0);
  static Color syntaxOption(bool dark) => Color(dark ? 0xff67d4df : 0xff087e8b);

  static double codeFontSizeOf(BuildContext context) =>
      Theme.of(context).extension<CodeTypography>()?.size ?? 14;

  /// 对话正文基准字号，再乘阅读倍率。
  static const messageBase = MobileType.body;

  static double messageScaleOf(BuildContext context) =>
      Theme.of(context).extension<ReadingTypography>()?.scale ?? 1;

  static TextStyle messageStyleOf(BuildContext context) => Theme.of(context)
      .textTheme
      .bodyLarge!
      .copyWith(fontSize: messageBase * messageScaleOf(context), height: 1.55);

  /// 对话 Markdown 的 h1–h6：不小于正文，再乘阅读倍率。
  static List<double> headingSizesOf(BuildContext context) => [
    for (final size in const [
      20.0,
      MobileType.headline,
      MobileType.title,
      MobileType.body,
      MobileType.body,
      MobileType.body,
    ])
      size * messageScaleOf(context),
  ];

  /// 对话 Markdown 的段落间距：16 号字 1.55 行高本身带约 9 的行间留白。
  static const markdownGap = MobileSpace.xs;

  static TextStyle codeStyleOf(BuildContext context) => Theme.of(context)
      .textTheme
      .bodyMedium!
      .copyWith(
        fontFamily: 'monospace',
        fontSize: codeFontSizeOf(context),
        height: 1.5,
      );

  /// 对话里辅助文字的不透明度：比正文浅，手机上仍看得清。
  static const asideAlpha = 0.8;

  /// 时间、角标、统计等元数据（[MobileType.caption]）。
  static TextStyle metaStyleOf(BuildContext context, {Color? color}) =>
      Theme.of(context).textTheme.labelSmall!.copyWith(color: color);

  /// 说明与提示文字（[MobileType.secondary]）。
  static TextStyle hintStyleOf(BuildContext context, {Color? color}) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(color: color);

  static MobileStatusColors statusColorsOf(BuildContext context) =>
      Theme.of(context).extension<MobileStatusColors>() ??
      MobileStatusColors.forBrightness(Theme.of(context).brightness);

  static ThemeData build(
    Brightness brightness, {
    double codeFontSize = 14,
    double messageScale = 1,
    MobileAccent accent = MobileAccent.fallback,
  }) {
    final dark = brightness == Brightness.dark;
    final primary = accent.of(brightness);
    final n = accent == MobileAccent.amber
        ? (dark ? _Neutrals.warmDark : _Neutrals.warmLight)
        : (dark ? _Neutrals.plainDark : _Neutrals.plainLight);
    // White on the accent, as messenger buttons are; ink only on a pale
    // one (graphite in the dark).
    final onPrimary = primary.computeLuminance() > .5
        ? const Color(0xFF15171A)
        : Colors.white;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: onPrimary,
          surface: n.page,
          onSurface: n.ink,
          onSurfaceVariant: n.subtle,
          outlineVariant: n.line,
          surfaceContainerLowest: n.cell,
          surfaceContainerLow: n.cell,
          surfaceContainer: n.fill,
          surfaceContainerHigh: n.raised,
          surfaceContainerHighest: n.fill,
          surfaceBright: n.bar,
          secondaryContainer: n.chip,
          onSecondaryContainer: n.ink,
          outline: n.outline,
          error: dark ? const Color(0xFFFF6B6B) : const Color(0xFFE5484D),
        );
    final text = Typography.material2021().black
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
        .copyWith(
          titleLarge: TextStyle(
            fontSize: MobileType.headline,
            fontWeight: FontWeight.w600,
            height: 1.35,
            color: scheme.onSurface,
          ),
          titleMedium: TextStyle(
            fontSize: MobileType.title,
            fontWeight: FontWeight.w600,
            height: 1.3,
            color: scheme.onSurface,
          ),
          titleSmall: TextStyle(
            fontSize: MobileType.body,
            fontWeight: FontWeight.w600,
            height: 1.35,
            color: scheme.onSurface,
          ),
          bodyLarge: TextStyle(
            fontSize: MobileType.body,
            height: 1.5,
            color: scheme.onSurface,
          ),
          bodyMedium: TextStyle(
            fontSize: MobileType.body,
            height: 1.4,
            color: scheme.onSurface,
          ),
          bodySmall: TextStyle(
            fontSize: MobileType.secondary,
            height: 1.4,
            color: scheme.onSurfaceVariant,
          ),
          labelLarge: TextStyle(
            fontSize: MobileType.body,
            fontWeight: FontWeight.w500,
            color: scheme.onSurface,
          ),
          labelMedium: TextStyle(
            fontSize: MobileType.secondary,
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant,
          ),
          labelSmall: TextStyle(
            fontSize: MobileType.caption,
            height: 1.3,
            color: scheme.onSurfaceVariant,
          ),
        );
    final actionStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(
        Size(MobileSizes.control, MobileSizes.button),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MobileSizes.radius),
        ),
      ),
      textStyle: WidgetStatePropertyAll(text.labelLarge),
      tapTargetSize: MaterialTapTargetSize.padded,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          ...const PageTransitionsTheme().builders,
          TargetPlatform.android: const _MobilePageTransitionsBuilder(),
        },
      ),
      extensions: [
        CodeTypography(codeFontSize),
        ReadingTypography(messageScale),
        MobileStatusColors.forBrightness(brightness),
      ],
      scaffoldBackgroundColor: scheme.surface,
      dividerColor: scheme.outlineVariant,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: .5,
      ),
      hintColor: scheme.onSurfaceVariant,
      iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
        trackOutlineColor: WidgetStatePropertyAll(scheme.outline),
      ),
      sliderTheme: SliderThemeData(
        tickMarkShape: SliderTickMarkShape.noTickMark,
        inactiveTrackColor: scheme.onSurfaceVariant.withValues(alpha: .2),
      ),
      // Pressed, a row or button only greys over while the finger is down,
      // as phone apps do: no ripple spreading from the touch.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: scheme.onSurface.withValues(alpha: dark ? .10 : .07),
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleMedium,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 8,
        minTileHeight: MobileSizes.control,
        horizontalTitleGap: 12,
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyMedium,
        subtitleTextStyle: text.bodySmall,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        labelStyle: text.bodyMedium,
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        helperStyle: text.bodySmall,
        errorStyle: text.bodySmall?.copyWith(color: scheme.error),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MobileSizes.radius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MobileSizes.radius),
          borderSide: BorderSide(color: scheme.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: actionStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: actionStyle),
      textButtonTheme: TextButtonThemeData(style: actionStyle),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size(MobileSizes.control, MobileSizes.control),
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MobileSizes.radius),
        ),
        textStyle: text.bodyMedium,
      ),
      // 和常见手机 App 一样：标题不比顶栏大，说明用次要字号的灰字，
      // 两边多留点，按钮在底部一行平分（见 dialogButtons）。
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium?.copyWith(
          fontSize: MobileType.secondary,
          height: 1.5,
          color: scheme.onSurfaceVariant,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      ),
      // 一行小提示：窄一些、矮一些、圆角小一点，不挡住正在写的地方。
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        contentTextStyle: text.bodySmall?.copyWith(
          color: scheme.onInverseSurface,
          fontSize: MobileType.secondary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MobileSizes.radius),
        ),
        elevation: 2,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: scheme.primary.withValues(alpha: .2),
      ),
    );
  }
}

/// 设置没变就给同一份主题：新建的主题总算不相等，整个应用会跟着重跑一遍过渡。
class MobileThemeCache {
  (MobileAccent, double, double)? _key;
  late ({ThemeData light, ThemeData dark}) _themes;

  ({ThemeData light, ThemeData dark}) of({
    required MobileAccent accent,
    required double codeFontSize,
    required double messageScale,
  }) {
    final key = (accent, codeFontSize, messageScale);
    if (key != _key) {
      ThemeData build(Brightness brightness) => MobileTheme.build(
        brightness,
        accent: accent,
        codeFontSize: codeFontSize,
        messageScale: messageScale,
      );
      _key = key;
      _themes = (light: build(Brightness.light), dark: build(Brightness.dark));
    }
    return _themes;
  }
}

@immutable
class ReadingTypography extends ThemeExtension<ReadingTypography> {
  const ReadingTypography(this.scale);
  final double scale;
  @override
  ReadingTypography copyWith({double? scale}) =>
      ReadingTypography(scale ?? this.scale);
  @override
  ReadingTypography lerp(covariant ReadingTypography? other, double t) =>
      ReadingTypography(
        other == null ? scale : scale + (other.scale - scale) * t,
      );
}

@immutable
class CodeTypography extends ThemeExtension<CodeTypography> {
  const CodeTypography(this.size);
  final double size;
  @override
  CodeTypography copyWith({double? size}) => CodeTypography(size ?? this.size);
  @override
  CodeTypography lerp(covariant CodeTypography? other, double t) =>
      CodeTypography(other == null ? size : size + (other.size - size) * t);
}

@immutable
class MobileStatusColors extends ThemeExtension<MobileStatusColors> {
  const MobileStatusColors({
    required this.success,
    required this.warning,
    required this.info,
    required this.added,
    required this.removed,
    required this.addedBackground,
    required this.removedBackground,
  });
  factory MobileStatusColors.forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    // What a state means stays its own color whatever the accent: green
    // done or online, indigo under way (calm beside any accent, not
    // the loud link blue), orange careful, red (the scheme's error)
    // waiting on you or failed.
    return MobileStatusColors(
      success: Color(dark ? 0xFF4CC38A : 0xFF12A150),
      warning: Color(dark ? 0xFFF3A847 : 0xFFD46B08),
      info: Color(dark ? 0xFF7D7AFF : 0xFF5856D6),
      added: Color(dark ? 0xFF91C99B : 0xFF356B43),
      removed: Color(dark ? 0xFFF1A49E : 0xFFA43E37),
      addedBackground: Color(dark ? 0xFF2D4A35 : 0xFFD2E9D7),
      removedBackground: Color(dark ? 0xFF5C3232 : 0xFFF6D3CF),
    );
  }
  final Color success,
      warning,
      info,
      added,
      removed,
      addedBackground,
      removedBackground;
  @override
  MobileStatusColors copyWith({
    Color? success,
    Color? warning,
    Color? info,
    Color? added,
    Color? removed,
    Color? addedBackground,
    Color? removedBackground,
  }) => MobileStatusColors(
    success: success ?? this.success,
    warning: warning ?? this.warning,
    info: info ?? this.info,
    added: added ?? this.added,
    removed: removed ?? this.removed,
    addedBackground: addedBackground ?? this.addedBackground,
    removedBackground: removedBackground ?? this.removedBackground,
  );
  @override
  MobileStatusColors lerp(covariant MobileStatusColors? other, double t) =>
      other == null
      ? this
      : MobileStatusColors(
          success: Color.lerp(success, other.success, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
          info: Color.lerp(info, other.info, t)!,
          added: Color.lerp(added, other.added, t)!,
          removed: Color.lerp(removed, other.removed, t)!,
          addedBackground: Color.lerp(
            addedBackground,
            other.addedBackground,
            t,
          )!,
          removedBackground: Color.lerp(
            removedBackground,
            other.removedBackground,
            t,
          )!,
        );
}
