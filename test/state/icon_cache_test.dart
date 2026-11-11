import 'dart:async';
import 'dart:convert';

import 'package:baocode_mobile/state/icon_cache.dart';
import 'package:flutter_test/flutter_test.dart';

const _pngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  test('decodes the base64 payload of a successful request', () async {
    final cache = IconCache();
    final bytes = await cache.get(
      'desktop',
      'icon',
      'abc',
      request: (_, _, _) async => {'data': _pngB64, 'type': 'image/png'},
    );
    expect(bytes, base64Decode(_pngB64));
  });

  test('concurrent callers share one request', () async {
    var calls = 0;
    final cache = IconCache();
    final completer = Completer<Object?>();
    Future<Object?> request(_, _, _) async {
      calls++;
      return completer.future;
    }

    final first = cache.get('d', 'icon', 'x', request: request);
    final second = cache.get('d', 'icon', 'x', request: request);
    completer.complete({'data': _pngB64, 'type': 'image/png'});
    expect(await first, isNotNull);
    expect(await second, isNotNull);
    expect(calls, 1);
  });

  test(
    'a completed fetch is served from cache without a new request',
    () async {
      var calls = 0;
      final cache = IconCache();
      Future<Object?> request(_, _, _) async {
        calls++;
        return {'data': _pngB64, 'type': 'image/png'};
      }

      await cache.get('d', 'botAvatar', 'bot-1', request: request);
      await cache.get('d', 'botAvatar', 'bot-1', request: request);
      expect(calls, 1);
    },
  );

  test('different ids and desktops do not collide', () async {
    var calls = 0;
    final cache = IconCache();
    Future<Object?> request(_, _, _) async {
      calls++;
      return {'data': _pngB64, 'type': 'image/png'};
    }

    await cache.get('d', 'icon', 'a', request: request);
    await cache.get('d', 'icon', 'b', request: request);
    await cache.get('other', 'icon', 'a', request: request);
    expect(calls, 3);
  });

  test('failures return null instead of throwing, and allow a retry', () async {
    var calls = 0;
    final cache = IconCache();
    Future<Object?> request(_, _, _) async {
      calls++;
      throw StateError('desktop is offline');
    }

    expect(await cache.get('d', 'icon', 'x', request: request), isNull);
    expect(await cache.get('d', 'icon', 'x', request: request), isNull);
    expect(calls, 2, reason: 'a failed fetch must not poison the cache');
  });

  test('invalidating a desktop drops only its entries', () async {
    var calls = 0;
    final cache = IconCache();
    Future<Object?> request(_, _, _) async {
      calls++;
      return {'data': _pngB64, 'type': 'image/png'};
    }

    await cache.get('d1', 'icon', 'x', request: request);
    await cache.get('d2', 'icon', 'x', request: request);
    cache.invalidateDesktop('d1');
    await cache.get('d2', 'icon', 'x', request: request);
    expect(calls, 2, reason: 'd2 must stay cached');
    await cache.get('d1', 'icon', 'x', request: request);
    expect(calls, 3, reason: 'd1 was invalidated and re-requested');
  });

  test('oldest entries are evicted beyond maxEntries', () async {
    var calls = 0;
    final cache = IconCache(maxEntries: 2);
    Future<Object?> request(_, method, params) async {
      calls++;
      return {'data': _pngB64, 'type': 'image/png'};
    }

    await cache.get('d', 'icon', 'a', request: request);
    await cache.get('d', 'icon', 'b', request: request);
    await cache.get('d', 'icon', 'c', request: request);
    await cache.get('d', 'icon', 'a', request: request);
    expect(calls, 4, reason: 'a was evicted by c and re-requested');
    await cache.get('d', 'icon', 'c', request: request);
    expect(calls, 4, reason: 'c is still cached');
  });

  test('non-map or dataless answers are treated as failures', () async {
    final cache = IconCache();
    expect(
      await cache.get('d', 'icon', 'x', request: (_, _, _) async => 'nope'),
      isNull,
    );
    expect(
      await cache.get(
        'd',
        'icon',
        'x',
        request: (_, _, _) async => {'type': 'image/png'},
      ),
      isNull,
    );
    expect(
      await cache.get(
        'd',
        'icon',
        'x',
        request: (_, _, _) async => {'data': '*not base64*', 'type': 'x'},
      ),
      isNull,
    );
  });
}
