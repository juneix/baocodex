import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A bundled Lucide line icon, colored like [Icon] from the [IconTheme].
class LucideIcon extends StatelessWidget {
  const LucideIcon(this.name, {super.key, this.size = 20, this.color});

  final String name;
  final double size;
  final Color? color;

  /// Reads [names] into the SVG cache, so the first screen after a cold
  /// start does not draw without its icons while they load from the APK.
  static Future<void> precache(Iterable<String> names) => Future.wait([
    for (final name in names)
      SvgAssetLoader(_path(name)).loadBytes(null).then((_) {}),
  ]);

  static String _path(String name) => 'assets/icons/lucide-$name.svg';

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    _path(name),
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(
      color ??
          IconTheme.of(context).color ??
          Theme.of(context).colorScheme.onSurfaceVariant,
      BlendMode.srcIn,
    ),
  );
}
