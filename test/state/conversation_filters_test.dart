import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/conversations/conversation_filters.dart';
import 'package:flutter_test/flutter_test.dart';

SessionRef task(
  String desktop,
  String id,
  String project, {
  LinkSessionStatus status = LinkSessionStatus.idle,
  bool pinned = false,
  int day = 1,
}) => SessionRef(
  desktop,
  SessionSummary(
    id: id,
    project: project,
    title: id,
    updatedAt: DateTime(2026, 11, day),
    status: status,
    pinned: pinned,
  ),
);

void main() {
  test('来源使用含用户名端口的原始标识而不是根路径', () {
    expect(projectSource(r'C:\Work\mobile'), ConversationSource.local);
    expect(projectSource('/home/dev/mobile'), ConversationSource.local);
    expect(
      projectSource('ssh://user@host:2222/home/dev/mobile'),
      ConversationSource.ssh,
    );
    expect(
      projectSource('ssh://wsl+Ubuntu/home/dev/mobile'),
      ConversationSource.wsl,
    );
    expect(projectSource('ssh://devbox/'), ConversationSource.ssh);
    expect(projectSource('ssh://wsl+Ubuntu/'), ConversationSource.wsl);
    expect(projectSource('ssh:///missing'), ConversationSource.unknown);
    expect(projectSource('future://host/project'), ConversationSource.unknown);
  });
  test('SSH 主机名去掉用户名和端口，WSL 与本地没有', () {
    expect(sshHostOf('ssh://root@armbian:2222/home/dev/mobile'), 'armbian');
    expect(sshHostOf('ssh://armbian/home/dev/mobile'), 'armbian');
    expect(sshHostOf('ssh://wsl+Ubuntu/home/dev/mobile'), isNull);
    expect(sshHostOf('/home/dev/mobile'), isNull);
    expect(sshHostOf(r'C:\Work\mobile'), isNull);
    expect(sshHostOf('ssh:///missing'), isNull);
  });

  test('同名项目按电脑隔离且待处理与运行使用同一条件', () {
    const projects = [
      ProjectRef('a', ProjectInfo(id: '/p', name: 'mobile', path: '/p')),
      ProjectRef('b', ProjectInfo(id: '/p', name: 'mobile', path: '/p')),
    ];
    final sessions = [
      task('a', 'idle', '/p'),
      task('a', 'question', '/p', status: LinkSessionStatus.needsInput),
      task('b', 'other', '/p', status: LinkSessionStatus.running),
    ];
    final result = const ConversationFilters(
      projectKey: ('a', '/p'),
      status: ConversationStatus.active,
    ).projects(projects, sessions, (id) => id);
    expect(result.length, 1);
    expect(result.single.sessions.map((s) => s.session.id), ['question']);
  });
  test('搜索和来源状态组合并保留项目置顶优先', () {
    const projects = [
      ProjectRef(
        'a',
        ProjectInfo(id: 'ssh://dev/p', name: 'mobile', path: '/p'),
      ),
      ProjectRef(
        'a',
        ProjectInfo(id: '/local', name: 'mobile', path: '/local'),
      ),
      ProjectRef(
        'a',
        ProjectInfo(
          id: 'ssh://dev/q',
          name: 'mobile old',
          path: '/q',
          pinned: true,
        ),
      ),
    ];
    final sessions = [
      task('a', 'remote', 'ssh://dev/p', day: 3),
      task('a', 'local', '/local'),
      task('a', 'pinned-project', 'ssh://dev/q'),
    ];
    final result = const ConversationFilters(
      query: 'mobile',
      source: ConversationSource.ssh,
    ).projects(projects, sessions, (id) => id);
    expect(result.map((p) => p.ref.project.id), ['ssh://dev/q', 'ssh://dev/p']);
  });
  test('SSH 范围同时包含两类远程项目但不含本机', () {
    const projects = [
      ProjectRef('a', ProjectInfo(id: 'ssh://dev/p', name: 'ssh', path: '/p')),
      ProjectRef(
        'a',
        ProjectInfo(id: 'ssh://wsl+Ubuntu/q', name: 'wsl', path: '/q'),
      ),
      ProjectRef(
        'a',
        ProjectInfo(id: r'C:\Work\r', name: 'local', path: r'C:\Work\r'),
      ),
      ProjectRef(
        'a',
        ProjectInfo(id: 'future://x/y', name: 'unknown', path: '/y'),
      ),
    ];
    final names = const ConversationFilters(source: ConversationSource.remote)
        .projects(projects, [], (id) => id)
        .map((p) => p.ref.project.name);
    expect(names, unorderedEquals(['ssh', 'wsl']));
  });
  test('失去已选项目不改选同名项目，活跃筛选不显示空项目', () {
    const projects = [
      ProjectRef('b', ProjectInfo(id: '/p', name: 'mobile', path: '/p')),
    ];
    expect(
      const ConversationFilters(projectKey: ('a', '/p'))
          .projects(projects, [], (id) => id),
      isEmpty,
    );
    expect(
      const ConversationFilters(status: ConversationStatus.active)
          .projects(projects, [], (id) => id),
      isEmpty,
    );
    expect(
      const ConversationFilters().projects(projects, [], (id) => id),
      hasLength(1),
    );
  });
}
