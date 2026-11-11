import 'dart:convert';
import 'dart:typed_data';

import '../models/session_buffer.dart';

class DraftImage {
  const DraftImage(this.name, this.type, this.bytes);
  final String name, type;
  final Uint8List bytes;

  Map<String, Object?> get wire => {
    'name': name,
    'type': type,
    'data': base64Encode(bytes),
  };
}

class InputDraft {
  const InputDraft({
    this.text = '',
    this.images = const [],
    this.mentions = const {},
    this.imagesMissing = false,
  });

  final String text;
  final List<DraftImage> images;
  final Set<String> mentions;
  final bool imagesMissing;

  factory InputDraft.fromStored(Object? value) {
    if (value is String) return InputDraft(text: value);
    if (value is! Map) return const InputDraft();
    return InputDraft(
      text: value['text'] is String ? value['text'] as String : '',
      mentions: value['mentions'] is List
          ? (value['mentions'] as List).whereType<String>().toSet()
          : const {},
      imagesMissing: value['imagesPending'] == true,
    );
  }

  Map<String, Object?> toStored() => {
    'text': text,
    'mentions': mentions.toList(),
    if (images.isNotEmpty || imagesMissing) 'imagesPending': true,
  };

  bool get isEmpty =>
      text.isEmpty && images.isEmpty && mentions.isEmpty && !imagesMissing;

  InputDraft afterSending(InputDraft sent) {
    final remainingText = text == sent.text ? '' : text;
    return InputDraft(
      text: remainingText,
      images: [
        for (final image in images)
          if (!sent.images.contains(image)) image,
      ],
      mentions: {
        for (final path in mentions)
          if (remainingText.contains('@$path')) path,
      },
      imagesMissing: imagesMissing,
    );
  }
}

/// 协议没有稳定消息 ID：有发送时间的消息按内容和时间认定，窗口移位后跟到新位置；
/// 没有时间的（如 Codex）要求位置不变且此前的用户消息都没变。认不准就拒绝，不改错对象。
class MessageEditAnchor {
  const MessageEditAnchor._(
    this.index,
    this.at,
    this.message,
    this.history,
    this.desktopId,
    this.sessionId,
  );
  final int index;
  final Object? at;
  final String message, history, desktopId, sessionId;

  factory MessageEditAnchor.capture(SessionBuffer buffer, int index) {
    if (index < 0 || index >= buffer.items.length) {
      throw const FormatException('编辑目标已变化');
    }
    final item = buffer.items[index];
    return MessageEditAnchor._(
      index,
      item is Map ? item['at'] : null,
      _stable(item),
      _userHistory(buffer, index),
      buffer.desktopId,
      buffer.sessionId,
    );
  }

  // 耗时和用量在回合结束时才写回用户消息，不算消息变化。
  static String _stable(Object? item) => jsonEncode(
    item is Map
        ? {
            for (final entry in item.entries)
              if (entry.key != 'worked' && entry.key != 'usage')
                entry.key: entry.value,
          }
        : item,
  );

  static String _userHistory(SessionBuffer buffer, int index) => jsonEncode([
    for (var i = 0; i < index; i++)
      if (buffer.items[i] case {'t': 'user'} && final item) [i, _stable(item)],
  ]);

  /// 这条消息现在的位置；认不准时为 null。
  int? locate(SessionBuffer buffer) {
    if (buffer.desktopId != desktopId || buffer.sessionId != sessionId) {
      return null;
    }
    final items = buffer.items;
    if (at == null) {
      return index < items.length &&
              _stable(items[index]) == message &&
              _userHistory(buffer, index) == history
          ? index
          : null;
    }
    int? found;
    for (var i = 0; i < items.length; i++) {
      if (items[i] case {'at': final time} && final item
          when time == at && _stable(item) == message) {
        if (found != null) return null;
        found = i;
      }
    }
    return found;
  }

  bool matches(SessionBuffer buffer) => locate(buffer) != null;
}
