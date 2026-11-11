import 'package:bao_link/bao_link.dart';

import '../../state/app_state.dart';

/// 筛选只用 all / local / remote（官方面板把 SSH 与 WSL 合为一段）；
/// ssh / wsl / unknown 是单个项目的来源，用于角标。
enum ConversationSource { all, local, remote, ssh, wsl, unknown }

enum ConversationSort { recent, name }

enum ConversationStatus { all, active, pinned }

ConversationSource projectSource(String location) {
  if (location.startsWith('ssh://')) {
    final rest = location.substring(6);
    final slash = rest.indexOf('/');
    if (slash <= 0) return ConversationSource.unknown;
    final host = rest.substring(0, slash);
    if (host == 'wsl+') return ConversationSource.unknown;
    return host.startsWith('wsl+')
        ? ConversationSource.wsl
        : ConversationSource.ssh;
  }
  if (location.isEmpty || location.contains('://')) {
    return ConversationSource.unknown;
  }
  return ConversationSource.local;
}

class ConversationProject {
  const ConversationProject(this.ref, this.sessions);
  final ProjectRef ref;
  final List<SessionRef> sessions;
  DateTime? get activity => sessions.isEmpty
      ? null
      : sessions
            .map((s) => s.session.updatedAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
}

class ConversationFilters {
  const ConversationFilters({
    this.query = '',
    this.source = ConversationSource.all,
    this.sort = ConversationSort.recent,
    this.projectKey,
    this.status = ConversationStatus.all,
  });
  final String query;
  final ConversationSource source;
  final ConversationSort sort;
  final (String, String)? projectKey;
  final ConversationStatus status;
  bool get allowsBots =>
      source == ConversationSource.all &&
      projectKey == null &&
      status == ConversationStatus.all;
  bool get restricted =>
      !allowsBots || query.trim().isNotEmpty || sort != ConversationSort.recent;

  ConversationFilters copyWith({
    String? query,
    ConversationSource? source,
    ConversationSort? sort,
    (String, String)? projectKey,
    bool clearProject = false,
    ConversationStatus? status,
  }) => ConversationFilters(
    query: query ?? this.query,
    source: source ?? this.source,
    sort: sort ?? this.sort,
    projectKey: clearProject ? null : projectKey ?? this.projectKey,
    status: status ?? this.status,
  );

  /// Whether a project at [id] (its location) is in the chosen 范围.
  bool sourceMatches(String id) => switch (source) {
    ConversationSource.all => true,
    ConversationSource.remote => const {
      ConversationSource.ssh,
      ConversationSource.wsl,
    }.contains(projectSource(id)),
    _ => projectSource(id) == source,
  };

  bool _projectMatches(String desktop, String id) =>
      (projectKey == null || projectKey == (desktop, id)) && sourceMatches(id);

  List<SessionRef> sessions(
    Iterable<SessionRef> input,
    String Function(String) desktopName, {
    String projectName = '',
    bool pinnedFirst = true,
  }) {
    final needle = query.trim().toLowerCase();
    final result = input
        .where(
          (ref) =>
              _projectMatches(ref.desktopId, ref.session.project) &&
              (status != ConversationStatus.active ||
                  ref.session.status != LinkSessionStatus.idle) &&
              (status != ConversationStatus.pinned || ref.session.pinned) &&
              '$projectName ${desktopName(ref.desktopId)} ${ref.session.title}'
                  .toLowerCase()
                  .contains(needle),
        )
        .toList();
    result.sort((a, b) {
      if (pinnedFirst && a.session.pinned != b.session.pinned) {
        return a.session.pinned ? -1 : 1;
      }
      final order = sort == ConversationSort.name
          ? a.session.title.toLowerCase().compareTo(
              b.session.title.toLowerCase(),
            )
          : b.session.updatedAt.compareTo(a.session.updatedAt);
      if (order != 0) return order;
      final desktop = a.desktopId.compareTo(b.desktopId);
      return desktop != 0 ? desktop : a.session.id.compareTo(b.session.id);
    });
    return result;
  }

  List<ConversationProject> projects(
    Iterable<ProjectRef> input,
    List<SessionRef> allSessions,
    String Function(String) desktopName,
  ) {
    final original = input.toList();
    final order = {
      for (var i = 0; i < original.length; i++)
        (original[i].desktopId, original[i].project.id): i,
    };
    final needle = query.trim().toLowerCase();
    final result = <ConversationProject>[];
    for (final ref in original) {
      if (!_projectMatches(ref.desktopId, ref.project.id)) continue;
      final matching = sessions(
        allSessions.where(
          (s) =>
              s.desktopId == ref.desktopId &&
              s.session.project == ref.project.id,
        ),
        desktopName,
        projectName: ref.project.name,
      );
      if (matching.isEmpty &&
          (status != ConversationStatus.all ||
              !'${ref.project.name} ${desktopName(ref.desktopId)}'
                  .toLowerCase()
                  .contains(needle))) {
        continue;
      }
      result.add(ConversationProject(ref, matching));
    }
    result.sort((a, b) {
      if ((a.ref.project.pinned == true) != (b.ref.project.pinned == true)) {
        return a.ref.project.pinned == true ? -1 : 1;
      }
      if (sort == ConversationSort.name) {
        final name = a.ref.project.name.toLowerCase().compareTo(
          b.ref.project.name.toLowerCase(),
        );
        if (name != 0) return name;
        final desktop = desktopName(a.ref.desktopId)
            .compareTo(desktopName(b.ref.desktopId));
        if (desktop != 0) return desktop;
        final id = a.ref.desktopId.compareTo(b.ref.desktopId);
        return id != 0 ? id : a.ref.project.id.compareTo(b.ref.project.id);
      } else {
        final at = a.activity, bt = b.activity;
        if (at != null && bt == null) return -1;
        if (at == null && bt != null) return 1;
        if (at != null && bt != null) {
          final time = bt.compareTo(at);
          if (time != 0) return time;
        }
      }
      return order[(a.ref.desktopId, a.ref.project.id)]!.compareTo(
        order[(b.ref.desktopId, b.ref.project.id)]!,
      );
    });
    return result;
  }
}
