import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../link/desktop_address.dart' show AddressResolutionException;
import '../link/phone_link.dart' show PairingStorageException;
import '../models/user_facing_error.dart';
import '../platform/file_export.dart' show DownloadTooLargeException;
import '../state/app_state.dart';

/// 用户看得到的错误，都在这里说成一句人话：界面别的地方不要再写
/// `'$error'` 或 `error.toString()`——那会把异常类名、errno 直接甩给用户。
///
/// 本地化沿用界面上的 [AppState.tr]，和按钮、标题用同一套语言。
String userMessage(AppState state, Object? error) => switch (error) {
  UserFacingError(:final message) => message,
  DownloadTooLargeException() => state.tr(
    '文件超过手机下载上限（8 MiB）。',
    'The file is over the 8 MiB download limit.',
  ),
  AddressResolutionException() => state.tr(
    '无法解析连接地址，请检查域名和 DNS。',
    'Cannot resolve the desktop address. Check the hostname and DNS.',
  ),
  PairingStorageException() => state.tr(
    '取消未完成，请在电脑端撤销手机授权。',
    'Cancellation could not be saved. Revoke this phone on the desktop.',
  ),
  LinkRemoteException(:final code) => switch (code) {
    LinkErrors.unpaired || LinkErrors.badToken => state.tr(
      '电脑不再认可这台手机，请重新配对。',
      'The desktop no longer trusts this phone. Pair again.',
    ),
    LinkErrors.notFound => state.tr(
      '电脑上找不到这项内容。',
      'The desktop has no such item.',
    ),
    LinkErrors.busy => state.tr(
      '电脑正忙，请稍后再试。',
      'The desktop is busy. Try again in a moment.',
    ),
    LinkErrors.unsupported || LinkErrors.unknown => state.tr(
      '电脑端版本过旧，暂不支持这个操作。',
      'The desktop is too old for this. Update it and try again.',
    ),
    LinkErrors.unreachable => state.tr(
      '电脑连不上那台远程机器。',
      'The desktop cannot reach that remote machine.',
    ),
    _ => state.tr('电脑没有完成这个请求。', 'The desktop did not complete the request.'),
  },
  PlatformException() => state.tr(
    '手机系统没能完成这个操作，请稍后重试。',
    'The phone could not complete that. Try again in a moment.',
  ),
  TimeoutException() => state.tr(
    '电脑没有及时回应，请检查网络后重试。',
    'The desktop did not answer in time. Check the network and retry.',
  ),
  FormatException() => state.tr(
    '电脑返回的内容无法识别，请更新电脑端后重试。',
    'The desktop sent something unreadable. Update it and retry.',
  ),
  _ => state.tr('操作没有成功，请稍后重试。', 'That did not work. Try again in a moment.'),
};
