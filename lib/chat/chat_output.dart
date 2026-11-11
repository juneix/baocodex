// YCode — GPL-3.0-only.
import 'chat_models.dart';
import '../link/chat_codec.dart';
import 'step_folds.dart';

/// One display row of the conversation, as the desktop history lays it
/// out: a single item (a thought merged with its run, a step, the agent's
/// words), or the line of a fold — a run of quick steps, or a finished
/// turn's work — that opens to the items it holds.
class TurnFooterData {
  const TurnFooterData({
    this.answer,
    this.worked,
    this.usage,
    this.live,
    this.since,
  });
  final String? answer;
  final Duration? worked;
  final TurnUsage? usage;
  final TurnOutput? live;
  final DateTime? since;
}

class ChatRow {
  const ChatRow.single(
    this.index,
    this.item,
    this.shown, {
    this.footer,
    this.showItem = true,
  }) : steps = null,
       work = null,
       edits = null,
       at = null,
       foldItems = const [];

  const ChatRow.fold(
    this.index,
    this.item,
    this.shown, {
    required this.steps,
    required this.work,
    required this.foldItems,
    this.at,
  }) : footer = null,
       showItem = true,
       edits = null,
       assert(steps != null || work != null);

  /// The line of a run of edits, [editsFoldMin] or more in a row.
  const ChatRow.edits(
    this.index,
    this.item,
    this.shown, {
    required StepFold this.edits,
    required this.foldItems,
  }) : footer = null,
       showItem = true,
       at = null,
       steps = null,
       work = null;

  final TurnFooterData? footer;
  final bool showItem;

  /// The wire index of the row's first item, so edit requests keep
  /// matching the buffer.
  final int index;

  /// The row's raw wire entry.
  final Object? item;

  /// The row's item as the wire kind, thoughts of a run merged.
  final ChatItem? shown;

  /// The run of quick steps starting here; null otherwise.
  final StepFold? steps;

  /// The turn's work starting here; null otherwise.
  final StepFold? work;

  /// The run of edits starting here; null otherwise. Its key never meets a
  /// steps fold's: edits are no quick steps, so none starts where it does.
  final StepFold? edits;

  /// 这一行要写上的时刻；只有 Bot 聊天里没有消息带时间的回合才有。
  final DateTime? at;

  /// The fold's items, decoded; what a steps line counts and a work line
  /// tallies.
  final List<ChatItem> foldItems;

  bool get isFold => steps != null || work != null || edits != null;
}

/// The decoded items, in order (unknown wire entries stay placeholders, so
/// indexes keep matching the buffer).
List<ChatItem?> decodeItems(List<Object?> entries) {
  ChatItem? decode(Object? entry) {
    try {
      return entry is ChatItem ? entry : ChatCodec.decode(entry);
    } catch (_) {
      return null;
    }
  }

  return [for (final entry in entries) decode(entry)];
}

/// Which plan the desktop would start, and the history as it should read.
///
/// The desktop's `startPlan` starts "its history's plan item awaiting": the
/// latest plan, put to the user and not yet answered. So only that one is
/// pending, and only while the user has said nothing after it; nor one the
/// desktop already answered `notFound` for ([lost], by [planKey]). Every
/// other plan still marked awaiting reads [PlanStatus.expired], so its card
/// and the start button never disagree.
({int? pending, List<Object?> items}) pendingPlans(
  List<Object?> items, {
  Set<String> lost = const {},
}) {
  final decoded = decodeItems(items);
  int? pending;
  for (var i = decoded.length - 1; i >= 0; i--) {
    final item = decoded[i];
    if (item is UserMessageItem) break;
    if (item is PlanItem) {
      if (item.status == PlanStatus.awaiting && !lost.contains(planKey(item))) {
        pending = i;
      }
      break;
    }
  }
  return (
    pending: pending,
    items: [
      for (final (i, item) in decoded.indexed)
        if (item case final PlanItem plan
            when plan.status == PlanStatus.awaiting && i != pending)
          PlanItem(
            path: plan.path,
            round: plan.round,
            title: plan.title,
            text: plan.text,
            status: PlanStatus.expired,
            writes: plan.writes,
            feedback: plan.feedback,
          )
        else
          items[i],
    ],
  );
}

/// Tells one plan from another within a conversation.
String planKey(PlanItem plan) => '${plan.round}:${plan.path}';

/// 和 Bot 的聊天只显示说的话和发的东西；App 发给它的内部通知和干活的过程不算。
bool shownInBotChat(ChatItem? item) => switch (item) {
  null || AssistantTextItem() || NoticeItem() => true,
  final UserMessageItem user => ChatCodec.botEvent(user) == null,
  ToolCallItem(:final input) when input['sticker'] is String => true,
  final ToolCallItem tool when ChatCodec.botImageUrl(tool) != null => true,
  final ChatItem item => standsOutOfWork(item),
};

/// Bot 聊天的行：每个做完的回合在最后一句话前有一行“已处理”，过程收在它
/// 里面，点开另看。
List<ChatRow> botRows(List<Object?> items) {
  final decoded = decodeItems(items);
  ChatItem at(int index) =>
      decoded[index] ?? const NoticeItem(NoticeKind.info, '');
  final lines = <int, (StepFold, UserMessageItem)>{};
  for (var prompt = 0; prompt < items.length; prompt++) {
    final message = decoded[prompt];
    if (message is! UserMessageItem || message.worked == null) continue;
    var end = prompt + 1;
    while (end < items.length && decoded[end] is! UserMessageItem) {
      end++;
    }
    var answer = end - 1;
    while (answer > prompt && decoded[answer] is! AssistantTextItem) {
      answer--;
    }
    if (answer == prompt) continue;
    lines[answer] = (
      StepFold(StepFoldKind.work, prompt + 1, end, worked: message.worked),
      message,
    );
  }
  final rows = <ChatRow>[];
  for (var i = 0; i < items.length; i++) {
    if (lines[i] case (final fold, final prompt)) {
      rows.add(
        ChatRow.fold(
          i,
          items[i],
          at(i),
          steps: null,
          work: fold,
          foldItems: [
            for (var j = fold.start; j < fold.end; j++)
              if (!shownInBotChat(decoded[j]) && decoded[j] is! LiveStatusItem)
                at(j),
          ],
          // 由内部通知唤醒的回合没有消息带时间，写在这一行上。
          at: ChatCodec.botEvent(prompt) == null ? null : prompt.sentAt,
        ),
      );
    }
    if (shownInBotChat(decoded[i])) {
      rows.add(ChatRow.single(i, items[i], at(i)));
    }
  }
  return rows;
}

/// The rows a history shows, folded the desktop way: each run of at least
/// two quick steps into one line, each finished turn's work into one line
/// before its answer. [isOpen] says which folds stand open.
List<ChatRow> foldRows(
  List<Object?> items, {
  required bool live,
  required bool Function(StepFold fold) isOpen,
  int? keepOpenFrom,
}) {
  final decoded = decodeItems(items);
  ChatItem at(int index) =>
      decoded[index] ?? const NoticeItem(NoticeKind.info, '');
  final folds = StepFolds.of(
    items.length,
    at,
    live: live,
    keepOpenFrom: keepOpenFrom,
  );
  final endings = <int, int>{};
  for (var end = 0; end < items.length; end++) {
    final prompt = folds.turnEndingAt(end);
    if (prompt == null) continue;
    var target = end;
    var sawNotice = false;
    while (target > prompt &&
        (decoded[target] is NoticeItem || decoded[target] is ThinkingItem)) {
      sawNotice = sawNotice || decoded[target] is NoticeItem;
      target--;
    }
    if (!sawNotice || decoded[target] is! AssistantTextItem) target = end;
    endings[target] = prompt;
  }
  // A finished turn no footer carries the answer of (an old history with
  // no statistics, say) still gets its copy/quote under its last words:
  // only there, never under the paragraphs between, nor in a turn under way.
  final fallbackEnds = <int>{};
  var turnStart = 0;
  for (var next = 1; next <= items.length; next++) {
    if (next < items.length && decoded[next] is! UserMessageItem) continue;
    final start = turnStart;
    turnStart = next;
    if (live && next == items.length) continue;
    var last = next - 1;
    while (last >= start && decoded[last] is! AssistantTextItem) {
      last--;
    }
    if (last < start) continue;
    var covered = false;
    // The turn's one tail (on its last row, text or tool alike) carries the
    // copy/quote words too, so no second footer is needed.
    for (var end = start; end < next; end++) {
      final prompt = endings[end];
      if (prompt != null && at(prompt) is UserMessageItem) covered = true;
    }
    if (!covered) fallbackEnds.add(last);
  }
  final rows = <ChatRow>[];
  for (var i = 0; i < items.length; i++) {
    final item = at(i);
    final row = folds.rowAt(i, item, isOpen);
    TurnFooterData? footer;
    if (fallbackEnds.contains(i) && item is AssistantTextItem) {
      footer = TurnFooterData(answer: item.text);
    }
    final prompt = endings[i];
    final message = prompt == null ? null : at(prompt);
    if (message is UserMessageItem && prompt != null) {
      final words = <String>[];
      for (var j = i; j > prompt; j--) {
        final part = at(j);
        if (part is AssistantTextItem) {
          words.insert(0, part.text);
        } else if (part is! ThinkingItem) {
          break;
        }
      }
      // A tail that is not words (a tool) still carries the turn's last
      // words for copy/quote.
      if (words.isEmpty) {
        for (var j = i; j > prompt; j--) {
          if (at(j) case AssistantTextItem(:final text)) {
            words.add(text);
            break;
          }
        }
      }
      footer = TurnFooterData(
        answer: words.isEmpty ? null : words.join('\n\n'),
        worked: message.worked,
        usage: message.usage,
      );
    }
    if (item case LiveStatusItem(:final output, :final startedAt)
        when live &&
            i == items.length - 1 &&
            (startedAt != null || (output?.tokens ?? 0) > 0)) {
      footer = TurnFooterData(
        live: output ?? const TurnOutput(tokens: 0),
        since: startedAt,
      );
    }
    // A fold's line leads its run; the run's items follow as their own
    // rows while it stands open, and hide while closed (a run under way
    // shows its last step even closed).
    if (row.work ?? row.steps case final fold?) {
      rows.add(
        ChatRow.fold(
          i,
          items[i],
          folds.shownAt(i, item),
          steps: row.steps,
          work: row.work,
          foldItems: [for (var j = fold.start; j < fold.end; j++) ?decoded[j]],
        ),
      );
    } else if (row.item || footer != null) {
      rows.add(
        ChatRow.single(
          i,
          items[i],
          folds.shownAt(i, item),
          footer: footer,
          showItem: row.item,
        ),
      );
    }
  }
  return _foldEdits(rows, isOpen);
}

/// How many edits in a row fold into one line: fewer read as they are.
const editsFoldMin = 3;

/// [rows] with each run of [editsFoldMin] or more edits behind one line
/// ("编辑 5 次 +40 −3"), its edits following while it stands open: a
/// turn under way that touches many files stays short on a phone.
List<ChatRow> _foldEdits(
  List<ChatRow> rows,
  bool Function(StepFold fold) isOpen,
) {
  bool isEdit(ChatRow row) =>
      !row.isFold &&
      row.showItem &&
      row.footer == null &&
      row.shown is CodeDiffItem;
  final folded = <ChatRow>[];
  var start = 0;
  while (start < rows.length) {
    if (!isEdit(rows[start])) {
      folded.add(rows[start++]);
      continue;
    }
    var end = start;
    while (end < rows.length && isEdit(rows[end])) {
      end++;
    }
    final run = rows.sublist(start, end);
    start = end;
    if (run.length < editsFoldMin) {
      folded.addAll(run);
      continue;
    }
    final fold = StepFold(
      StepFoldKind.steps,
      run.first.index,
      run.last.index + 1,
    );
    folded.add(
      ChatRow.edits(
        run.first.index,
        run.first.item,
        run.first.shown,
        edits: fold,
        foldItems: [for (final row in run) row.shown!],
      ),
    );
    if (isOpen(fold)) folded.addAll(run);
  }
  return folded;
}
