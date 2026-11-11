import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/apk_download.dart';
import '../../state/app_state.dart';
import '../../state/update_check.dart';
import '../../theme/app_theme.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.state,
    required this.release,
    this.downloader,
    this.installer = const AndroidUpdateInstaller(),
  });

  final AppState state;
  final ReleaseInfo release;
  final ApkDownloader? downloader;
  final AndroidUpdateInstaller installer;

  /// 有更新窗口开着：手动检查和打开应用时的自动检查都不再弹第二个。
  static bool get isOpen => _UpdateDialogState._open > 0;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  static int _open = 0;

  late final _downloader = widget.downloader ?? ApkDownloader();
  File? _file;
  int _received = 0;
  bool _busy = false;
  bool _opened = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _open++;
  }

  @override
  void dispose() {
    _open--;
    _downloader.cancel();
    super.dispose();
  }

  Future<void> _downloadAndInstall() async {
    if (_busy || _opened) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final state = widget.state;
    try {
      if (_file == null) {
        final directory = await widget.installer.directory();
        if (!mounted) return;
        _file = await _downloader.download(
          widget.release.apk!,
          directory,
          onProgress: (received) {
            if (mounted) setState(() => _received = received);
          },
        );
      }
      if (!mounted) return;
      final opened = await widget.installer.install(_file!, widget.release);
      if (!mounted) return;
      setState(() {
        _opened = opened;
        _message = opened
            ? state.tr(
                '已打开系统安装器，请按系统提示完成安装。',
                'The system installer is open. Follow its instructions to finish.',
              )
            : state.tr(
                '请允许 YCode 安装应用，返回后点击「继续安装」。',
                'Allow YCode to install apps, then return and tap Continue installation.',
              );
      });
    } on ApkDownloadCancelled {
      if (mounted) {
        setState(() => _message = state.tr('下载已取消。', 'Download cancelled.'));
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = switch (error.code) {
          'invalid_update' => state.tr(
            '安装包校验失败：包名、签名或版本不匹配，请重新下载正式版本。',
            'Package verification failed. Download the official version with a matching package, signature, and version.',
          ),
          'unsupported_device' => state.tr(
            '此安装包仅支持 arm64 Android 设备。',
            'This package requires an arm64 Android device.',
          ),
          _ => state.tr(
            '无法打开安装器，请检查系统设置后重试。',
            'Could not open the installer. Check system settings and retry.',
          ),
        };
        // 校验失败不能反复安装同一个文件；重试重新下载。
        if (error.code == 'invalid_update') {
          _file = null;
          _received = 0;
        }
      });
    } on ApkDownloadException catch (error) {
      if (mounted) {
        setState(() {
          _received = 0;
          _message = _failureMessage(state, error.reason);
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _received = 0;
          _message = _failureMessage(state, ApkDownloadFailure.network);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _failureMessage(AppState state, ApkDownloadFailure reason) =>
      switch (reason) {
        ApkDownloadFailure.network => state.tr(
          '下载失败，请检查网络后重试。',
          'Download failed. Check your network and retry.',
        ),
        ApkDownloadFailure.incomplete => state.tr(
          '下载的文件不完整，请重新下载。',
          'The download was incomplete. Download it again.',
        ),
        ApkDownloadFailure.storage => state.tr(
          '无法保存安装包，请检查手机存储空间后重试。',
          'Could not save the package. Check your phone storage and retry.',
        ),
      };

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final release = widget.release;
    final apk = release.apk;
    final theme = Theme.of(context);
    final downloading = _busy && _file == null;
    return AlertDialog(
      title: Text(
        state.tr(
          '发现新版本 ${release.version}',
          'Version ${release.version} is available',
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (release.notes.isNotEmpty) ...[
              Text(
                state.tr('更新说明', 'Release notes'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: MobileSpace.sm),
              SelectableText(release.notes, style: theme.textTheme.bodySmall),
            ] else
              Text(
                state.tr('这次没有附带更新说明。', 'This release has no notes.'),
                style: MobileTheme.hintStyleOf(context),
              ),
            const SizedBox(height: MobileSpace.md),
            if (apk == null)
              Text(
                state.tr(
                  '此版本尚未提供可用的 Android 安装包。',
                  'No compatible Android package is available for this release yet.',
                ),
              )
            else ...[
              Text(
                'Android arm64 · ${(apk.size / (1024 * 1024)).toStringAsFixed(1)} MiB',
                style: MobileTheme.hintStyleOf(context),
              ),
              if (downloading) ...[
                const SizedBox(height: MobileSpace.sm),
                LinearProgressIndicator(value: _received / apk.size),
                const SizedBox(height: MobileSpace.sm),
                Text(
                  state.tr(
                    '正在下载 ${(_received * 100 / apk.size).floor()}%',
                    'Downloading ${(_received * 100 / apk.size).floor()}%',
                  ),
                ),
              ],
            ],
            if (_message != null) ...[
              const SizedBox(height: MobileSpace.sm),
              Semantics(liveRegion: true, child: Text(_message!)),
            ],
          ],
        ),
      ),
      actions: dialogButtons([
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            downloading
                ? state.tr('取消下载', 'Cancel download')
                : state.tr(
                    _opened || apk == null ? '关闭' : '以后再说',
                    _opened || apk == null ? 'Close' : 'Later',
                  ),
          ),
        ),
        if (apk != null && !_opened)
          FilledButton(
            onPressed: _busy ? null : _downloadAndInstall,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _file == null
                        ? state.tr('下载并安装', 'Download and install')
                        : state.tr('继续安装', 'Continue installation'),
                  ),
          ),
      ]),
    );
  }
}
