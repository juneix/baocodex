import 'dart:async';

import 'package:bao_link/bao_link.dart';

import 'phone_link.dart' show PairingStorageException;
import 'desktop_address.dart' show AddressResolutionException;

String connectionCheckErrorMessage(Object error, LinkTranslate tr) {
  if (error is AddressResolutionException) {
    return tr(
      '域名解析失败或超时，请检查域名和 DNS。',
      'DNS lookup failed or timed out. Check the hostname and DNS.',
    );
  }
  if (error is LinkRemoteException &&
      (error.code == LinkErrors.unpaired ||
          error.code == LinkErrors.badToken)) {
    return tr(
      '电脑未认可当前授权，请重新配对。',
      'The desktop no longer trusts this phone. Pair again.',
    );
  }
  if (error is TimeoutException) {
    return tr(
      '电脑响应超时，请检查地址、端口和电脑是否在线。',
      'The desktop timed out. Check its address, port and online status.',
    );
  }
  if (error is FormatException) {
    return tr(
      '电脑返回的连接状态无效。',
      'The desktop returned an invalid connection state.',
    );
  }
  return tr(
    '连接检查失败，请检查网络、地址、端口及电脑授权。',
    'Connection check failed. Check the network, address, port and desktop authorization.',
  );
}

typedef LinkTranslate = String Function(String chinese, String english);

/// Pairing failures must never echo a URI containing a one-time token.
String pairingErrorMessage(Object error, LinkTranslate tr) {
  if (error is PairingStorageException) {
    return tr(
      '取消未完成，已保存的信任可能仍存在。请在电脑端撤销手机授权，并重新打开应用检查已配对电脑。',
      'Cancellation could not be saved. Trust may remain. Revoke this phone on the desktop and check paired desktops after reopening the app.',
    );
  }
  if (error is PairingVersionException) {
    return error.older
        ? tr(
            '请先更新电脑端 BaoCode，再重新扫码配对。',
            'Update BaoCode on the computer, then scan its new pairing code.',
          )
        : tr(
            '请先更新手机端 BaoCode，再重新扫码配对。',
            'Update BaoCode on this phone, then scan the pairing code again.',
          );
  }
  if (error is FormatException) {
    return tr(
      '配对链接无效或已过期，请在电脑上显示新二维码。',
      'The pairing link is invalid or expired. Show a new code on the computer.',
    );
  }
  if (error is LinkRemoteException) {
    return switch (error.code) {
      LinkErrors.busy => tr(
        '电脑正在与另一台手机配对，请稍后再试。',
        'The computer is pairing another phone. Try again in a moment.',
      ),
      LinkErrors.notPairing => tr(
        '请先在电脑上打开配对窗口。',
        'Open the pairing window on the computer first.',
      ),
      LinkErrors.rejected => tr(
        '电脑拒绝了配对请求。',
        'The computer declined the pairing request.',
      ),
      LinkErrors.badToken => tr(
        '配对链接已失效，请在电脑上显示新二维码。',
        'This pairing link is no longer valid. Show a new code on the computer.',
      ),
      _ => tr(
        '配对未完成，请在电脑端检查授权后重试。',
        'Pairing did not finish. Check approval on the computer and try again.',
      ),
    };
  }
  if (error is TimeoutException) {
    return tr(
      '电脑响应超时，请检查电脑端是否需要确认。',
      'The computer timed out. Check whether it is waiting for approval.',
    );
  }
  return tr(
    '无法连接电脑，请检查地址和网络后重试。',
    'Cannot reach the computer. Check the address and network, then retry.',
  );
}
