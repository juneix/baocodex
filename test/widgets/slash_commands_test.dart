import 'package:baocode_mobile/ui/tasks/slash_commands.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String tr(String zh, String en) => zh;

  test('只在打命令名时弹出：/ 开头、还没空格', () {
    expect(slashQuery('/'), '');
    expect(slashQuery('/comp'), 'comp');
    expect(slashQuery('/compact '), isNull);
    expect(slashQuery('看看 /compact'), isNull);
    expect(slashQuery(''), isNull);
  });

  test('名字含输入的排出来，开头对上的在前，同名只留先来的', () {
    final commands = [
      ...builtinSlashCommands(tr),
      const SlashCommand('review', '技能', kind: SlashKind.skill),
      const SlashCommand('code-review', '同名技能', kind: SlashKind.skill),
    ];
    final hits = matchSlashCommands(commands, 'review');
    expect(hits.map((command) => command.name), [
      'review',
      'security-review',
      'code-review',
    ]);
    expect(hits.last.kind, SlashKind.skill);
    expect(hits.last.description, isNot('同名技能'));
    expect(
      matchSlashCommands(commands, '').length,
      builtinSlashCommands(tr).length + 1,
    );
  });

  test('内置列表不再有 Claude Code 已去掉的 /review', () {
    final names = builtinSlashCommands(tr).map((command) => command.name);
    expect(names, isNot(contains('review')));
    expect(names, containsAll(['goal', 'recap', 'insights', 'rename']));
  });

  group('项目命令文件', () {
    test('说明和参数提示取自开头的 --- 块', () {
      final command = projectSlashCommand('deploy.md', '''
---
description: "部署到测试环境"
argument-hint: [环境]
allowed-tools: Bash
---
# 部署
跑脚本
''')!;
      expect(command.name, 'deploy');
      expect(command.description, '部署到测试环境');
      expect(command.hint, '[环境]');
      expect(command.kind, SlashKind.command);
      expect(command.project, isTrue);
    });

    test('没写说明就用正文第一行，去掉标题井号', () {
      final command = projectSlashCommand('fix.md', '\n## 修复问题\n细节')!;
      expect(command.description, '修复问题');
      expect(command.hint, '');
      expect(
        projectSlashCommand(
          'empty.md',
          '---\ndescription:\n---\n正文',
        )!.description,
        '正文',
      );
    });

    test('> 和 | 写的多行说明并成一行', () {
      expect(
        projectSlashCommand('a.md', '''
---
description: >-
  第一行
  第二行
argument-hint: [x]
---
''')!.description,
        '第一行 第二行',
      );
      final command = projectSlashCommand(
        'b.md',
        '---\r\ndescription: |\r\n  甲\r\n\r\n  乙\r\nargument-hint: [y]\r\n---\r\n',
      )!;
      expect(command.description, '甲 乙');
      expect(command.hint, '[y]');
    });

    test('不是 .md 的不算', () {
      expect(projectSlashCommand('notes.txt', 'x'), isNull);
      expect(projectSlashCommand('.md', 'x'), isNull);
    });
  });

  testWidgets('菜单显示参数提示和项目标签', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlashCommandMenu(
            projectLabel: '项目',
            onPick: (_) {},
            commands: const [
              SlashCommand('rename', '重命名对话', hint: '[名字]'),
              SlashCommand(
                'deploy',
                '部署',
                kind: SlashKind.command,
                project: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('[名字]  重命名对话'), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
  });
}
