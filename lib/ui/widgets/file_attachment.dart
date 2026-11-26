import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/material_file_icons.dart';

String attachmentSize(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

/// 没有大小时用扩展名说是什么文件，如 PDF；没有扩展名就不写。
String? attachmentType(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return null;
  final ext = name.substring(dot + 1);
  return ext.length > 8 ? null : ext.toUpperCase();
}

/// 待发与历史文件共用类型图标、主题与文字排布；历史没有大小时不猜测。
class FileAttachment extends StatelessWidget {
  const FileAttachment({
    super.key,
    required this.name,
    this.path,
    this.size,
    this.status,
    this.detail,
    this.uploading = false,
    this.failed = false,
    this.onRemove,
    this.onTap,
    this.removeLabel,
    this.bot = false,
    this.nameLines = 2,
  });
  final String name;
  final String? path, status, detail, removeLabel;
  final int? size;
  final bool uploading, failed, bot;
  final VoidCallback? onRemove, onTap;

  /// 输入框上方与缩略图等高时只放一行名字。
  final int nameLines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = name.isEmpty
        ? AppState.phrase('所选文件', 'Selected file')
        : name;
    // 失败时原因比大小重要，占两行说清楚；上传中只说进度，窄卡片放不下大小。
    final metadata = (failed || uploading) && status != null
        ? status!
        : [
            if (size case final size?)
              attachmentSize(size)
            else if (status == null)
              ?attachmentType(label),
            ?status,
          ].join(' · ');
    final secondary = failed ? scheme.error : scheme.onSurfaceVariant;
    return Tooltip(
      message: [label, ?path, ?detail].join('\n'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          key: const ValueKey('file-attachment'),
          padding: const EdgeInsets.all(MobileSpace.sm),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            border: Border.all(color: scheme.outlineVariant, width: .5),
            borderRadius: BorderRadius.circular(bot ? 6 : 12),
          ),
          child: Row(
            children: [
              FileIcon(name, size: 24),
              const SizedBox(width: MobileSpace.sm),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: nameLines,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (metadata.isNotEmpty) ...[
                      const SizedBox(height: MobileSpace.xs),
                      Row(
                        children: [
                          if (uploading) ...[
                            SizedBox(
                              key: const ValueKey('file-upload-progress'),
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: secondary,
                              ),
                            ),
                            const SizedBox(width: MobileSpace.xs),
                          ],
                          Expanded(
                            child: Text(
                              metadata,
                              maxLines: failed ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: secondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (onRemove != null)
                Tooltip(
                  message:
                      removeLabel ?? AppState.phrase('移除文件', 'Remove file'),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onRemove,
                    child: SizedBox.square(
                      dimension: 28,
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
