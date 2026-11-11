// YCode — GPL-3.0-only.
import 'package:flutter/material.dart';

/// Per-extension icons for the file tree, standing in for the original
/// app's `ui/files/file_icons.dart`. Folders keep their own glyph.
IconData fileIcon(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'webp' ||
    'svg' ||
    'bmp' => Icons.image_outlined,
    'mp4' || 'mov' || 'avi' || 'mkv' || 'webm' => Icons.movie_outlined,
    'mp3' || 'wav' || 'flac' || 'm4a' || 'ogg' => Icons.music_note_outlined,
    'pdf' => Icons.picture_as_pdf_outlined,
    'doc' || 'docx' || 'odt' || 'rtf' => Icons.description_outlined,
    'xls' || 'xlsx' || 'ods' || 'csv' => Icons.table_chart_outlined,
    'ppt' || 'pptx' || 'odp' => Icons.slideshow_outlined,
    'zip' || 'tar' || 'gz' || 'rar' || '7z' => Icons.folder_zip_outlined,
    'yaml' ||
    'yml' ||
    'toml' ||
    'json' ||
    'lock' ||
    'ini' ||
    'properties' => Icons.tune_outlined,
    'dart' ||
    'js' ||
    'jsx' ||
    'ts' ||
    'tsx' ||
    'py' ||
    'java' ||
    'kt' ||
    'kts' ||
    'go' ||
    'rs' ||
    'c' ||
    'cc' ||
    'cpp' ||
    'h' ||
    'hpp' ||
    'cs' ||
    'swift' ||
    'rb' ||
    'php' => Icons.code_outlined,
    'html' || 'htm' => Icons.language_outlined,
    'css' || 'scss' => Icons.style_outlined,
    'sh' || 'bat' || 'ps1' => Icons.terminal_outlined,
    'md' || 'markdown' => Icons.article_outlined,
    'ttf' || 'otf' || 'woff' || 'woff2' => Icons.font_download_outlined,
    _ => Icons.description_outlined,
  };
}
