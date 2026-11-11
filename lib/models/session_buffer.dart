import 'package:bao_link/bao_link.dart';

/// Keeps wire positions, including unknown items, so edit indexes stay valid.
class SessionBuffer {
  SessionBuffer(this.desktopId, this.sessionId);

  final String desktopId;
  final String sessionId;
  final List<Object?> items = [];
  bool live = false;
  bool? earlier;
  bool loadingEarlier = false;
  bool loading = false;
  String? error;
  Map<String, Object?>? interaction;
  Map<String, Object?>? goal;
  List<LinkChoice> choices = [];
  List<LinkTask> tasks = [];
  List<Map<String, Object?>> changes = [];
  int revision = 0;

  void apply(LinkSessionUpdate update, {bool snapshot = false}) {
    if (update.session != sessionId) {
      throw const FormatException('Session update belongs to another session');
    }
    final start = update.start;
    if (start < 0 ||
        update.count < start ||
        update.count != start + update.items.length ||
        (!snapshot && start > items.length) ||
        (snapshot && start != 0)) {
      throw const FormatException(
        'Invalid session delta; a snapshot is needed',
      );
    }
    if (snapshot) items.clear();
    items.replaceRange(start, items.length, update.items);
    live = update.live;
    earlier = update.earlier;
    interaction = update.interaction;
    choices = update.choices;
    tasks = update.tasks;
    changes = update.changes;
    goal = update.goal;
    error = null;
    revision++;
  }

  void prepend(Map<String, Object?> result) {
    final older = result['items'];
    if (older is! List) throw const FormatException('Invalid history page');
    items.insertAll(0, older);
    earlier = result['earlier'] == true;
    revision++;
  }
}

Map<String, Object?> objectMap(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, Object?>{};
