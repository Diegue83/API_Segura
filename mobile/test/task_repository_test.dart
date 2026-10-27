/// Verifies task JSON parsing and request payloads.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secure_task_manager/core/network/api_client.dart';
import 'package:secure_task_manager/features/auth/data/auth_repository.dart';
import 'package:secure_task_manager/features/tasks/data/task_repository.dart';

import 'fakes.dart';

const _base = 'http://localhost:3000/api/v1';

Map<String, dynamic> _task(String id, {bool completed = false}) => {
      'id': id,
      'ownerId': 'owner',
      'title': 'Task $id',
      'description': null,
      'completed': completed,
    };

void main() {
  test('parses a list of tasks', () async {
    final mock = MockClient((_) async => http.Response(
          jsonEncode({
            'items': [_task('c1'), _task('c2', completed: true)],
            'page': 1,
            'limit': 20,
          }),
          200,
        ));
    final repo = TaskRepository(ApiClient(mock, FakeTokenStore(), baseUrl: _base));

    final tasks = await repo.list();

    expect(tasks, hasLength(2));
    expect(tasks.last.completed, isTrue);
    expect(tasks.first.description, isNull);
  });

  test('parses an empty list', () async {
    final mock = MockClient(
      (_) async => http.Response(jsonEncode({'items': []}), 200),
    );
    final repo = TaskRepository(ApiClient(mock, FakeTokenStore(), baseUrl: _base));

    expect(await repo.list(), isEmpty);
  });

  test('create never sends an owner or user id', () async {
    late Map<String, dynamic> body;
    final mock = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'item': _task('c3')}), 201);
    });
    final repo = TaskRepository(ApiClient(mock, FakeTokenStore(), baseUrl: _base));

    await repo.create('  Title  ', '   ');

    expect(body, {'title': 'Title', 'description': null});
    expect(body.containsKey('ownerId'), isFalse);
  });

  test('logout clears local tokens even if the server is unreachable', () async {
    final mock = MockClient((_) async => throw Exception('offline'));
    final tokens = FakeTokenStore(accessToken: 'a', refreshToken: 'r');
    final repo = AuthRepository(ApiClient(mock, tokens, baseUrl: _base), tokens);

    await repo.logout();

    expect(tokens.cleared, isTrue);
    expect(await tokens.readRefreshToken(), isNull);
  });
}
