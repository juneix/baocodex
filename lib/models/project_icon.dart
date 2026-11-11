import 'package:flutter/foundation.dart';

/// A project's icon as the desktop keeps it in `ProjectInfo.icon`:
/// `{"type": "emoji", "emoji"}`, `{"type": "codicon", "name", "color"?}`,
/// `{"type": "image", "id"}` (fetched over [LinkMethods.icon]) or
/// `{"type": "brand", "name"}` (a model maker's logo name).
///
/// Mirrors the original app's `models/project_icon.dart` (AOT path evidence);
/// the wire shape is defined by the public protocol, not invented here.
@immutable
sealed class ProjectIcon {
  const ProjectIcon();

  static ProjectIcon? parse(Object? json) {
    if (json is! Map<String, Object?>) return null;
    switch (json['type']) {
      case 'emoji':
        final emoji = json['emoji'];
        if (emoji is String && emoji.isNotEmpty) return ProjectEmojiIcon(emoji);
      case 'codicon':
        final name = json['name'];
        if (name is String && name.isNotEmpty) {
          final color = json['color'];
          return ProjectCodiconIcon(
            name,
            color: color is String && color.isNotEmpty ? color : null,
          );
        }
      case 'image':
        final id = json['id'];
        if (id is String && id.isNotEmpty) return ProjectImageIcon(id);
      case 'brand':
        final name = json['name'];
        if (name is String && name.isNotEmpty) return ProjectBrandIcon(name);
    }
    return null;
  }
}

class ProjectEmojiIcon extends ProjectIcon {
  const ProjectEmojiIcon(this.emoji);
  final String emoji;
}

/// A VS Code codicon name in an optional theme color id. Only a small set of
/// names maps to Material glyphs here; unknown names fall back to a folder.
class ProjectCodiconIcon extends ProjectIcon {
  const ProjectCodiconIcon(this.name, {this.color});
  final String name;
  final String? color;
}

class ProjectImageIcon extends ProjectIcon {
  const ProjectImageIcon(this.id);
  final String id;
}

/// No RPC serves brand logos over the link; rendered as a labeled fallback.
class ProjectBrandIcon extends ProjectIcon {
  const ProjectBrandIcon(this.name);
  final String name;
}
