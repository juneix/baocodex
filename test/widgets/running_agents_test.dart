// YCode — GPL-3.0-only.
import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:baocode_mobile/ui/tasks/running_agents.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('按 task 顺序去重并保留首个同 id 消息', () {
    final first = AgentItem(
      id: 'tool-2',
      description: '首个消息卡片',
      status: CommandStatus.running,
    );
    final duplicate = AgentItem(
      id: 'tool-2',
      description: '重复消息卡片',
      status: CommandStatus.running,
    );
    final fallback = AgentItem(
      description: '仅消息卡片代理',
      status: CommandStatus.running,
    );
    final now = DateTime.utc(2026);
    final tasks = [
      LinkTask(
        id: 'task-2',
        kind: 'agent',
        description: 'task 优先详情',
        status: 'running',
        startedAt: now,
        toolUseId: 'tool-2',
      ),
      LinkTask(
        id: 'task-2-duplicate',
        kind: 'agent',
        description: '重复 task',
        status: 'running',
        startedAt: now,
        toolUseId: 'tool-2',
      ),
    ];

    final projected = projectRunningAgents([first, duplicate, fallback], tasks);

    expect(projected.map((entry) => entry.item?.description), [
      '首个消息卡片',
      '仅消息卡片代理',
    ]);
    expect(projected.map((entry) => entry.task?.description), [
      'task 优先详情',
      null,
    ]);
  });

  test('task 没有 toolUseId 时仍与首个无 id 代理配对', () {
    final agent = AgentItem(
      description: '无 id 代理',
      status: CommandStatus.running,
    );
    final task = LinkTask(
      id: 'task-null-tool',
      kind: 'agent',
      description: '有任务详情',
      status: 'running',
      startedAt: DateTime.utc(2026),
    );

    final projected = projectRunningAgents([agent], [task]);

    expect(projected.first.item, same(agent));
    expect(projected.first.task, same(task));
    expect(projected, hasLength(2));
    expect(projected.last.item, same(agent));
    expect(projected.last.task, isNull);
  });
}
