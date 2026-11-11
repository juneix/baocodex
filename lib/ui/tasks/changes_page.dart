// YCode — GPL-3.0-only.
import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/message_view.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/material_file_icons.dart' as material_icons;
import '../files/files_tab.dart';
import '../widgets/lucide_icon.dart';
import '../widgets/fold_row.dart';
import '../user_message.dart';

/// 会话中尚未保留的改动，顶部居中提供批量操作，每个文件也能单独处理。
class ChangesPage extends StatefulWidget {
  const ChangesPage({
    super.key,
    required this.state,
    required this.desktopId,
    required this.sessionId,
    this.projectId,
  });

  final AppState state;
  final String desktopId, sessionId;
  final String? projectId;

  @override
  State<ChangesPage> createState() => _ChangesPageState();
}

class _ChangesPageState extends State<ChangesPage> with ChangeActions {
  @override
  AppState get state => widget.state;
  @override
  String get desktopId => widget.desktopId;
  @override
  String get sessionId => widget.sessionId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final tr = state.tr;
      final bulkStyle = ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(
            horizontal: MobileSpace.lg,
            vertical: MobileSpace.sm,
          ),
        ),
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelMedium,
        ),
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
      );
      final changes = state.buffer(desktopId, sessionId).changes;
      final projectPath = _changeProjectPath(
        state,
        desktopId,
        sessionId,
        widget.projectId,
      );
      return Scaffold(
        appBar: AppBar(title: Text(tr('全部改动', 'All changes'))),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (busy) const LinearProgressIndicator(minHeight: 2),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  MobileSpace.lg,
                  MobileSpace.sm,
                  MobileSpace.lg,
                  0,
                ),
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(MobileSizes.radius),
                  clipBehavior: Clip.antiAlias,
                  child: SwitchListTile(
                    key: const ValueKey('auto-keep-changes'),
                    title: Text(tr('自动保留改动', 'Keep changes automatically')),
                    subtitle: Text(
                      tr('对所有对话生效，需连着电脑', 'All conversations, while connected'),
                    ),
                    value: state.settings.autoKeep,
                    onChanged: (value) {
                      state.settings.autoKeep = value;
                      unawaited(state.saveSettings());
                    },
                  ),
                ),
              ),
              if (error != null) ChangeError(error!),
              if (changes.isNotEmpty) ...[
                ChangeSummary(state: state, changes: changes),
                SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: MobileSpace.lg,
                      vertical: MobileSpace.sm,
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: MobileSpace.sm,
                      runSpacing: MobileSpace.xs,
                      children: [
                        OutlinedButton(
                          style: bulkStyle,
                          onPressed: enabled ? () => apply(true) : null,
                          child: Text(tr('全部撤回', 'Undo all')),
                        ),
                        FilledButton(
                          style: bulkStyle,
                          onPressed: enabled ? () => apply(false) : null,
                          child: Text(tr('全部保留', 'Keep all')),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              Expanded(
                child: changes.isEmpty
                    ? Center(
                        child: Text(
                          tr('没有待处理的文件更改', 'No unkept file changes'),
                          style: TextStyle(color: Theme.of(context).hintColor),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final change in changes)
                            ChangeFileRow(
                              state: state,
                              change: change,
                              projectPath: projectPath,
                              enabled: enabled,
                              onApply: (undo) =>
                                  apply(undo, '${change['path'] ?? ''}'),
                              onOpen: () => openChangeDiff(
                                context,
                                state,
                                desktopId: desktopId,
                                sessionId: sessionId,
                                projectId: widget.projectId,
                                path: '${change['path'] ?? ''}',
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The changed files of a conversation as rows, for the bar over a chat.
class ChangesPanel extends StatefulWidget {
  const ChangesPanel({
    super.key,
    required this.state,
    required this.desktopId,
    required this.sessionId,
    this.projectId,
  });
  final AppState state;
  final String desktopId, sessionId;
  final String? projectId;
  @override
  State<ChangesPanel> createState() => _ChangesPanelState();
}

class _ChangesPanelState extends State<ChangesPanel> with ChangeActions {
  @override
  AppState get state => widget.state;
  @override
  String get desktopId => widget.desktopId;
  @override
  String get sessionId => widget.sessionId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final changes = state.buffer(desktopId, sessionId).changes;
      final projectPath = _changeProjectPath(
        state,
        desktopId,
        sessionId,
        widget.projectId,
      );
      return ListView(
        primary: false,
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: MobileSpace.xs),
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          if (error != null) ChangeError(error!),
          for (final change in changes)
            ChangeFileRow(
              state: state,
              change: change,
              projectPath: projectPath,
              enabled: enabled,
              onApply: (undo) => apply(undo, '${change['path'] ?? ''}'),
              onOpen: () => openChangeDiff(
                context,
                state,
                desktopId: desktopId,
                sessionId: sessionId,
                projectId: widget.projectId,
                path: '${change['path'] ?? ''}',
              ),
            ),
        ],
      );
    },
  );
}

/// Keeps or undoes a conversation's changes: all of them, or one file's.
/// Undoing writes the files back, so it asks first.
mixin ChangeActions<T extends StatefulWidget> on State<T> {
  AppState get state;
  String get desktopId;
  String get sessionId;

  bool busy = false;
  String? error;

  bool get enabled => !busy && state.isOnline(desktopId);

  Future<void> apply(bool undo, [String? path]) async {
    if (!enabled) return;
    final tr = state.tr;
    if (undo) {
      final colors = Theme.of(context).colorScheme;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            path == null
                ? tr('撤回全部改动？', 'Undo all changes?')
                : tr('撤回这个文件的改动？', 'Undo this file\'s changes?'),
          ),
          content: Text(
            path == null
                ? tr(
                    '本对话尚未保留的文件会恢复到修改前。',
                    'Files this conversation changed and not kept go back to how they were.',
                  )
                : tr('$path 会恢复到修改前。', '$path goes back to how it was.'),
          ),
          actions: dialogButtons([
            OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('取消', 'Cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('撤回', 'Undo')),
            ),
          ]),
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (!enabled) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await state.request(
        desktopId,
        undo ? LinkMethods.undo : LinkMethods.keep,
        {
          'session': sessionId,
          'paths': ?(path == null ? null : [path]),
        },
      );
      // 电脑那边改完不一定马上推过来；自己再读一次，否则卡片还挂着旧的改动。
      if (mounted) {
        await state
            .refreshSession(desktopId, sessionId)
            .catchError((Object _) {});
      }
    } catch (failure) {
      if (mounted) setState(() => error = userMessage(state, failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

String? _changeProjectPath(
  AppState state,
  String desktopId,
  String sessionId,
  String? projectId,
) {
  final explicit = projectId?.trim();
  final id = explicit != null && explicit.isNotEmpty
      ? explicit
      : state.sessions
            .where(
              (ref) =>
                  ref.desktopId == desktopId && ref.session.id == sessionId,
            )
            .firstOrNull
            ?.session
            .project;
  return state.projects
      .where((ref) => ref.desktopId == desktopId && ref.project.id == id)
      .firstOrNull
      ?.project
      .path;
}

// 仅缩短显示；读取、复制与保留/撤回始终使用原始路径。
String? _changeFolder(String path, String? projectPath) {
  final normalized = path.replaceAll('\\', '/');
  final cut = normalized.lastIndexOf('/');
  if (cut < 0) return null;
  final folder = normalized.substring(0, cut);
  final root = projectPath
      ?.replaceAll('\\', '/')
      .replaceFirst(RegExp(r'/+$'), '');
  if (root != null && (root.isNotEmpty || projectPath == '/')) {
    final windows =
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized) ||
        normalized.startsWith('//');
    final comparedFolder = windows ? folder.toLowerCase() : folder;
    final comparedRoot = windows ? root.toLowerCase() : root;
    if (comparedFolder == comparedRoot) return '.';
    if (comparedFolder.startsWith('$comparedRoot/')) {
      return folder.substring(root.length + 1);
    }
  }
  return shortPath(folder);
}

(int, int) changeTotals(List<Map<String, Object?>> changes) => (
  changes.fold(0, (sum, c) => sum + ((c['added'] as num?)?.toInt() ?? 0)),
  changes.fold(0, (sum, c) => sum + ((c['removed'] as num?)?.toInt() ?? 0)),
);

/// 「+40 −8」 in the diff colours; nothing for a count that is not known.
class ChangeCounts extends StatelessWidget {
  const ChangeCounts({
    super.key,
    this.added,
    this.removed,
    this.compact = false,
  });
  final int? added, removed;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final colors = MobileTheme.statusColorsOf(context);
    final text = Theme.of(context).textTheme;
    final style = (compact ? text.labelSmall : text.labelMedium)!.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (added case final added? when added > 0)
            TextSpan(
              text: '+$added',
              style: TextStyle(color: colors.added),
            ),
          if ((added ?? 0) > 0 && (removed ?? 0) > 0) const TextSpan(text: ' '),
          if (removed case final removed? when removed > 0)
            TextSpan(
              text: '−$removed',
              style: TextStyle(color: colors.removed),
            ),
        ],
      ),
    );
  }
}

/// 「3 个文件 · +40 −8」 over the full list.
class ChangeSummary extends StatelessWidget {
  const ChangeSummary({super.key, required this.state, required this.changes});
  final AppState state;
  final List<Map<String, Object?>> changes;
  @override
  Widget build(BuildContext context) {
    final (added, removed) = changeTotals(changes);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MobileSpace.lg,
        MobileSpace.md,
        MobileSpace.lg,
        MobileSpace.xs,
      ),
      child: Wrap(
        spacing: MobileSpace.sm,
        runSpacing: MobileSpace.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            state.tr('${changes.length} 个文件', '${changes.length} files'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          ChangeCounts(added: added, removed: removed),
        ],
      ),
    );
  }
}

enum _ChangeFileAction { path, copy, keep, undo }

/// 文件名独占主行，目录和增删数在次行；低频操作收进菜单。
class ChangeFileRow extends StatelessWidget {
  const ChangeFileRow({
    super.key,
    required this.state,
    required this.change,
    required this.enabled,
    required this.onApply,
    required this.onOpen,
    this.projectPath,
  });
  final AppState state;
  final Map<String, Object?> change;
  final bool enabled;
  final ValueChanged<bool> onApply;
  final VoidCallback onOpen;
  final String? projectPath;

  String get path => '${change['path'] ?? ''}';

  Future<void> _copyPath(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: path));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.tr('路径已复制', 'Path copied'))),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(userMessage(state, error))));
      }
    }
  }

  void _showPath(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(state.tr('文件路径', 'File path')),
      content: SingleChildScrollView(child: SelectableText(path)),
      actions: dialogButtons([
        OutlinedButton(
          onPressed: () => _copyPath(context),
          child: Text(state.tr('复制路径', 'Copy path')),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(state.tr('关闭', 'Close')),
        ),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tr = state.tr;
    final cut = path.lastIndexOf(RegExp(r'[/\\]'));
    final name = path.substring(cut + 1);
    final folder = _changeFolder(path, projectPath);
    final added = (change['added'] as num?)?.toInt();
    final removed = (change['removed'] as num?)?.toInt();
    // 菜单与文件点击区分离，禁用的写操作不会误打开差异。
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                MobileSpace.lg,
                MobileSpace.md,
                0,
                MobileSpace.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: material_icons.FileIcon(path, size: 20),
                  ),
                  const SizedBox(width: MobileSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium!.copyWith(
                            fontSize: MobileType.secondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: MobileSpace.xs),
                        Tooltip(
                          message: path,
                          child: _ChangeFileMetadata(
                            folder: folder == '.'
                                ? tr('项目根目录', 'Project root')
                                : folder ?? '',
                            added: added,
                            removed: removed,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        PopupMenuButton<_ChangeFileAction>(
          tooltip: '${tr('文件操作', 'File actions')} $path',
          icon: const LucideIcon('ellipsis', size: 20),
          onSelected: (action) {
            switch (action) {
              case _ChangeFileAction.path:
                _showPath(context);
              case _ChangeFileAction.copy:
                _copyPath(context);
              case _ChangeFileAction.keep:
                if (enabled) onApply(false);
              case _ChangeFileAction.undo:
                if (enabled) onApply(true);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _ChangeFileAction.path,
              child: Text(tr('查看完整路径', 'Show full path')),
            ),
            PopupMenuItem(
              value: _ChangeFileAction.copy,
              child: Text(tr('复制完整路径', 'Copy full path')),
            ),
            PopupMenuItem(
              value: _ChangeFileAction.keep,
              enabled: enabled,
              child: Text(tr('保留改动', 'Keep changes')),
            ),
            PopupMenuItem(
              value: _ChangeFileAction.undo,
              enabled: enabled,
              child: Text(
                tr('撤回改动', 'Undo changes'),
                style: TextStyle(
                  color: enabled
                      ? theme.colorScheme.error
                      : theme.disabledColor,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 窄屏或大字号时计数另起一行，优先保留完整的末级目录。
class _ChangeFileMetadata extends StatelessWidget {
  const _ChangeFileMetadata({required this.folder, this.added, this.removed});
  final String folder;
  final int? added, removed;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final directory = _ChangeFolderLabel(folder);
      if ((added ?? 0) <= 0 && (removed ?? 0) <= 0) return directory;
      final counts = ChangeCounts(
        added: added,
        removed: removed,
        compact: true,
      );
      final minimumFolder = folder.contains('/')
          ? '…/${folder.split('/').last}'
          : folder;
      final countText = [
        if ((added ?? 0) > 0) '+$added',
        if ((removed ?? 0) > 0) '−$removed',
      ].join(' ');
      final painter = TextPainter(
        text: TextSpan(
          text: minimumFolder + countText,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final stacked = painter.width + MobileSpace.sm > constraints.maxWidth;
      painter.dispose();
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            directory,
            const SizedBox(height: MobileSpace.xs),
            counts,
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: directory),
          const SizedBox(width: MobileSpace.sm),
          counts,
        ],
      );
    },
  );
}

/// 按实际字号与可用宽度省略目录前缀，不依赖反转文字方向。
class _ChangeFolderLabel extends StatelessWidget {
  const _ChangeFolderLabel(this.folder);
  final String folder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = Theme.of(context).textTheme.labelSmall;
      final painter = TextPainter(
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      );
      bool fits(String value) {
        painter.text = TextSpan(text: value, style: style);
        painter.layout();
        return painter.width <= constraints.maxWidth;
      }

      var shown = folder;
      if (!fits(shown)) {
        final parts = folder.split('/');
        for (var i = 1; i < parts.length; i++) {
          shown = '…/${parts.sublist(i).join('/')}';
          if (fits(shown)) break;
        }
        if (!fits(shown)) {
          final tail = parts.last.characters.toList();
          var low = 0, high = tail.length;
          while (low < high) {
            final count = (low + high + 1) ~/ 2;
            if (fits('…${tail.sublist(tail.length - count).join()}')) {
              low = count;
            } else {
              high = count - 1;
            }
          }
          shown = '…${tail.sublist(tail.length - low).join()}';
        }
      }
      painter.dispose();
      return Text(
        shown,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    },
  );
}

class ChangeError extends StatelessWidget {
  const ChangeError(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      MobileSpace.lg,
      MobileSpace.sm,
      MobileSpace.lg,
      MobileSpace.xs,
    ),
    child: Text(
      message,
      style: TextStyle(
        color: Theme.of(context).colorScheme.error,
        fontSize: MobileType.secondary,
      ),
    ),
  );
}

/// The diff of [path] as the conversation changed it; the project is
/// [projectId] or, failing that, the conversation's own.
void openChangeDiff(
  BuildContext context,
  AppState state, {
  required String desktopId,
  required String sessionId,
  String? projectId,
  required String path,
}) {
  final tr = state.tr;
  var project = projectId?.trim();
  if (project == null || project.isEmpty) {
    project = state.sessions
        .where(
          (ref) => ref.desktopId == desktopId && ref.session.id == sessionId,
        )
        .map((ref) => ref.session.project.trim())
        .firstOrNull;
  }
  if (project == null || project.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            '无法确定此会话所属项目，暂时不能查看差异。',
            'Cannot determine this conversation\'s project, so the diff is unavailable.',
          ),
        ),
      ),
    );
    return;
  }
  FocusManager.instance.primaryFocus?.unfocus();
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ProjectFilePage(
        state: state,
        desktopId: desktopId,
        projectId: project!,
        path: path,
      ),
    ),
  );
}

class ProjectFilePage extends StatefulWidget {
  const ProjectFilePage({
    super.key,
    required this.state,
    required this.desktopId,
    required this.projectId,
    required this.path,
  });
  final AppState state;
  final String desktopId, projectId, path;
  @override
  State<ProjectFilePage> createState() => _ProjectFilePageState();
}

class _ProjectFilePageState extends State<ProjectFilePage> {
  Map? _result;
  String? _error;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.state.request(
        widget.desktopId,
        LinkMethods.read,
        {'project': widget.projectId, 'path': widget.path},
      );
      if (result is! Map) throw const FormatException('Invalid file response');
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = userMessage(widget.state, error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.state.tr;
    final path = widget.path;
    final cut = path.lastIndexOf(RegExp(r'[/\\]'));
    // As the file list shows it: within the project, cut short at the start.
    final folder = _changeFolder(
      path,
      _changeProjectPath(widget.state, widget.desktopId, '', widget.projectId),
    );
    return Scaffold(
      appBar: AppBar(
        // The file's name, its folder centred under it.
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              path.substring(cut + 1),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (folder != null && folder != '.') _ChangeFolderLabel(folder),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: tr('刷新', 'Refresh'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error == null &&
                _result?['binary'] != true &&
                _result?['tooLarge'] != true &&
                _result?['original'] is String &&
                _result?['text'] is String
          ? SafeArea(
              top: false,
              child: DiffView(
                before: _result!['original'] as String,
                after: _result!['text'] as String,
                tr: tr,
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) Text(_error!),
                if (_result?['binary'] == true)
                  Text(tr('二进制文件，无法显示文本。', 'Binary file; no text preview.')),
                if (_result?['tooLarge'] == true)
                  Text(tr('文件过大，无法读取。', 'File exceeds the read limit.')),
                if (_error == null &&
                    _result?['binary'] != true &&
                    _result?['tooLarge'] != true &&
                    _result?['original'] is! String &&
                    _result?['text'] is String)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      tr(
                        '无法取得修改前内容，以下仅显示当前文件内容，并非差异。',
                        'The content before the change is unavailable; only the current file is shown below, not a diff.',
                      ),
                    ),
                  ),
                if (_result?['original'] is String)
                  FoldRow(
                    title: Text(tr('更改前', 'Before changes')),
                    children: [CodePanel(code: _result!['original'] as String)],
                  ),
                if (_result?['text'] is String)
                  CodePanel(
                    code: _result!['text'] as String,
                    language: widget.path.split('.').last,
                  ),
              ],
            ),
    );
  }
}
