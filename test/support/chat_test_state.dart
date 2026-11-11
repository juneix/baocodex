// YCode — GPL-3.0-only.
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';

/// 一段放在内存里的对话，不连电脑。[zh] 固定界面语言；不给就走设置。
class ChatTestState extends AppState {
  ChatTestState({this.zh, super.demo = false})
    : super(store: MemoryLinkStore());

  final bool? zh;
  final history = SessionBuffer('desktop', 'session');
  bool online = true;

  void update() {
    history.revision++;
    notifyListeners();
  }

  @override
  String tr(String zh, String en) => switch (this.zh) {
    true => zh,
    false => en,
    null => super.tr(zh, en),
  };

  @override
  bool isOnline(String desktopId) => online;

  @override
  SessionBuffer buffer(String desktopId, String sessionId) => history;

  @override
  Future<void> openSession(String desktopId, String sessionId) async {}

  @override
  Future<void> closeSession(String desktopId, String sessionId) async {}
}
