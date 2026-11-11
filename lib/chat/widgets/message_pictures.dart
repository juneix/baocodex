// YCode — conversation UI. GPL-3.0-only.
import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/user_facing_error.dart';
import '../../state/app_state.dart';
import '../../ui/widgets/image_gallery.dart';
import '../../ui/user_message.dart';
import '../chat_links.dart';

class ProjectPicture extends StatefulWidget {
  const ProjectPicture({
    super.key,
    required this.state,
    required this.desktopId,
    required this.path,
    required this.label,
    this.projectId,
    this.botId,
  });
  final AppState state;
  final String desktopId, path, label;
  final String? projectId, botId;
  @override
  State<ProjectPicture> createState() => _ProjectPictureState();
}

class _ProjectPictureState extends State<ProjectPicture> {
  Uint8List? _bytes;
  bool _loading = false;
  String? _error;
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Typed literal: the wire payload is all-string, and tests match the record's runtime type.
      final result = await widget.state.request(
        widget.desktopId,
        LinkMethods.image,
        <String, String>{
          if (widget.projectId case final project?)
            'project': project
          else
            'bot': widget.botId!,
          'path': Uri.decodeFull(widget.path),
        },
      );
      if (result is! Map || result['data'] is! String) {
        throw UserFacingError(
          result is Map && result['tooLarge'] == true
              ? widget.state.tr(
                  '图片超过 8 MB，不能显示。',
                  'The image is over 8 MB and cannot be shown.',
                )
              : widget.state.tr(
                  '这张图片暂时读不到。',
                  'This image could not be loaded.',
                ),
        );
      }
      final bytes = base64Decode(result['data'] as String);
      if (bytes.length >= LinkLimits.image) {
        throw UserFacingError(
          widget.state.tr(
            '图片超过 8 MB，不能显示。',
            'The image is over 8 MB and cannot be shown.',
          ),
        );
      }
      if (mounted) setState(() => _bytes = bytes);
    } catch (error) {
      if (mounted) setState(() => _error = userMessage(widget.state, error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(widget.path);
    if (uri != null && ['http', 'https'].contains(uri.scheme)) {
      return TextButton.icon(
        onPressed: () =>
            confirmExternalLink(context, widget.state, widget.path),
        icon: const Icon(Icons.image_outlined),
        label: Text('${widget.label} ↗'),
      );
    }
    if (_bytes != null) {
      return MemoryPicture(bytes: _bytes!, name: widget.label);
    }
    return TextButton.icon(
      onPressed:
          _loading ||
              (widget.projectId == null && widget.botId == null) ||
              (uri?.hasScheme ?? false)
          ? null
          : _load,
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.image_outlined),
      label: Text(
        _error ??
            widget.state.tr(
              '加载图片：${widget.label}',
              'Load image: ${widget.label}',
            ),
      ),
    );
  }
}

/// 消息与待发附件共用的图片缩略图，点击后全屏缩放查看。
class MemoryPicture extends StatefulWidget {
  const MemoryPicture({
    super.key,
    required this.bytes,
    this.name,
    this.width,
    this.height = 160,
    this.fit = BoxFit.contain,
    this.group,
    this.index = 0,
  });
  final Uint8List bytes;
  final String? name;
  final double? width;
  final double height;
  final BoxFit fit;

  /// 同组图片（同一条消息或同一批待发附件）；点开后在组内左右翻看，
  /// 从 [index] 起。为空时只看这一张。
  final List<GalleryImage>? group;
  final int index;

  @override
  State<MemoryPicture> createState() => _MemoryPictureState();
}

class _MemoryPictureState extends State<MemoryPicture> {
  late MemoryImage _image;

  @override
  void initState() {
    super.initState();
    _image = MemoryImage(widget.bytes);
  }

  @override
  void didUpdateWidget(MemoryPicture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.bytes, _image.bytes) &&
        !listEquals(widget.bytes, _image.bytes)) {
      _image = MemoryImage(widget.bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    return GestureDetector(
      onTap: () => showImageGallery(
        context,
        widget.group ?? [GalleryImage(widget.bytes, name: name)],
        initialIndex: widget.group == null ? 0 : widget.index,
      ),
      child: Image(
        image: _image,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        semanticLabel: name,
        errorBuilder: (_, _, _) => const Text('Invalid image'),
      ),
    );
  }
}
