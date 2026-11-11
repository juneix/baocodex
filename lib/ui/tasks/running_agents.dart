// YCode — GPL-3.0-only.
import 'package:bao_link/bao_link.dart';

import '../../chat/chat_models.dart';

class RunningAgent {
  const RunningAgent({this.item, this.task});

  final AgentItem? item;
  final LinkTask? task;
}

List<RunningAgent> projectRunningAgents(
  Iterable<ChatItem> items,
  Iterable<LinkTask> tasks,
) {
  final agentsById = <String?, AgentItem>{};
  final agents = <AgentItem>[];
  for (final item in items) {
    if (item is! AgentItem) continue;
    agents.add(item);
    agentsById.putIfAbsent(item.id, () => item);
  }

  final result = <RunningAgent>[];
  final seen = <String>{};
  for (final task in tasks) {
    if (task.kind != 'agent' || task.status != 'running') continue;
    final item = agentsById[task.toolUseId];
    final identity = item?.id ?? task.toolUseId ?? task.id;
    if (seen.add(identity)) result.add(RunningAgent(item: item, task: task));
  }
  for (final item in agents) {
    if (item.status != CommandStatus.running) continue;
    if (seen.add(item.id ?? item.description)) {
      result.add(RunningAgent(item: item));
    }
  }
  return result;
}
