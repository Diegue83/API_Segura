/// Verifies refresh-and-retry, safe errors, and request building.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secure_task_manager/core/network/api_client.dart';

import 'fakes.dart';

const _base = 'http://localhost:3000/api/v1';

void main() {
  test('refreshes once on 401 and retries the original request once', () async {
    var originalCalls = 0;
    var refreshCalls = 0;
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        refreshCalls++;
        return http.Response(jsonEncode({
          'accessToken': 'new-access',
          'refreshToken': 'new-refresh',
        }), 200);
      }
      originalCalls++;
      if (originalCalls == 1) return http.Response('{}', 401);
      expect(request.headers['authorization'], 'Bearer new-access');
      return http.Response(jsonEncode({'items': []}), 200);
    });
    final tokens = FakeTokenStore(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
    );
    final client = ApiClient(mock, tokens, baseUrl: _base);

    await client.send('GET', 'tasks');

    expect(refreshCalls, 1);
    expect(originalCalls, 2);
    expect(tokens.savedAccessToken, 'new-access');
    expect(tokens.savedRefreshToken, 'new-refresh');
  });

  test('concurrent 401s share a single refresh request (single-flight)', () async {
    var refreshCalls = 0;
    final mock = MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        refreshCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response(
          jsonEncode({'accessToken': 'a2', 'refreshToken': 'r2'}),
          200,
        );
      }
      if (request.headers['authorization'] == 'Bearer a1') {
        return http.Response('{}', 401);
      }
      return http.Response(jsonEncode({'items': []}), 200);
    });
    final client = ApiClient(
      mock,
      FakeTokenStore(accessToken: 'a1', refreshToken: 'r1'),
      baseUrl: _base,
    );

    await Future.wait([
      client.send('GET', 'tasks'),
      client.send('GET', 'tasks'),
      client.send('GET', 'tasks'),
    ]);

    expect(refreshCalls, 1);
  });

  test('failed refresh clears tokens and notifies session expiration', () async {
    var expired = false;
    final mock = MockClient((request) async => http.Response('{}', 401));
    final tokens = FakeTokenStore(accessToken: 'a', refreshToken: 'r');
    final client = ApiClient(
      mock,
      tokens,
      baseUrl: _base,
      onSessionExpired: () => expired = true,
    );

    await expectLater(
      client.send('GET', 'tasks'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
    expect(tokens.cleared, isTrue);
    expect(expired, isTrue);
  });

  test('errors never contain tokens or raw server bodies', () async {
    final mock = MockClient((request) async => http.Response(
          '{"error":"PrismaClientKnownRequestError at /srv/app.js secret-token"}',
          500,
        ));
    final client = ApiClient(
      mock,
      FakeTokenStore(accessToken: 'secret-token', refreshToken: 'r'),
      baseUrl: _base,
    );

    try {
      await client.send('GET', 'tasks');
      fail('Expected ApiException');
    } on ApiException catch (error) {
      expect(error.message, isNot(contains('secret-token')));
      expect(error.message, isNot(contains('Prisma')));
      expect(error.statusCode, 500);
    }
  });

  test('a timeout becomes a safe connection error', () async {
    final mock = MockClient((request) => Completer<http.Response>().future);
    final client = ApiClient(mock, FakeTokenStore(), baseUrl: _base);

    await expectLater(
      client.send('GET', 'tasks').timeout(const Duration(seconds: 20)),
      throwsA(isA<ApiException>().having(
        (e) => e.message,
        'message',
        contains('Could not connect'),
      )),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('malformed JSON is reported as unexpected data', () async {
    final mock = MockClient((request) async => http.Response('not json', 200));
    final client = ApiClient(mock, FakeTokenStore(), baseUrl: _base);

    await expectLater(
      client.send('GET', 'tasks'),
      throwsA(isA<ApiException>().having(
        (e) => e.message,
        'message',
        'The server returned unexpected data.',
      )),
    );
  });

  test('keeps query strings out of the path and does not send tokens to login',
      () async {
    late http.BaseRequest captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'items': []}), 200);
    });
    final client = ApiClient(
      mock,
      FakeTokenStore(accessToken: 'a', refreshToken: 'r'),
      baseUrl: _base,
    );

    await client.send('GET', 'tasks?page=2&limit=5');
    expect(captured.url.path, '/api/v1/tasks');
    expect(captured.url.queryParameters, {'page': '2', 'limit': '5'});

    await client.send('POST', 'auth/login', body: {'email': 'x', 'password': 'y'});
    expect(captured.headers.containsKey('authorization'), isFalse);
  });

  test('a wrong login password yields a generic message without retrying', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      return http.Response('{"error":{"message":"x"}}', 401);
    });
    final client = ApiClient(mock, FakeTokenStore(), baseUrl: _base);

    await expectLater(
      client.send('POST', 'auth/login', body: {'email': 'a', 'password': 'b'}),
      throwsA(isA<ApiException>().having(
        (e) => e.message,
        'message',
        'Invalid email or password.',
      )),
    );
    expect(calls, 1);
  });
}
