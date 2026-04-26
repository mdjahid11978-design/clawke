import 'dart:convert';
import 'dart:io';

import 'package:client/services/media_resolver.dart';
import 'package:client/models/managed_task.dart';
import 'package:client/services/tasks_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordedRequest {
  final String method;
  final Uri uri;
  final Map<String, dynamic>? body;

  const _RecordedRequest(this.method, this.uri, this.body);
}

void main() {
  late HttpServer server;
  late List<_RecordedRequest> requests;

  setUp(() async {
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    MediaResolver.setBaseUrl('http://127.0.0.1:${server.port}');
    MediaResolver.setToken('');
    server.listen((request) async {
      Map<String, dynamic>? body;
      if (request.method != 'GET') {
        final raw = await utf8.decoder.bind(request).join();
        body = raw.isEmpty ? null : jsonDecode(raw) as Map<String, dynamic>;
      }
      requests.add(_RecordedRequest(request.method, request.uri, body));

      final response = switch ((request.method, request.uri.path)) {
        ('GET', '/api/tasks') => {
          'tasks': [
            {
              'id': 'task_1',
              'account_id': request.uri.queryParameters['account_id'],
              'agent': 'Hermes',
              'name': 'Daily',
              'schedule': '0 9 * * *',
              'prompt': 'Summarize',
              'enabled': true,
              'status': 'active',
              'skills': ['notes'],
            },
          ],
        },
        ('POST', '/api/tasks') => {
          'task': {
            'id': 'task_new',
            'account_id': body?['account_id'],
            'agent': 'Hermes',
            'name': body?['name'],
            'schedule': body?['schedule'],
            'prompt': body?['prompt'],
            'enabled': body?['enabled'],
            'status': 'active',
            'skills': body?['skills'] ?? [],
            'deliver': body?['deliver'],
          },
        },
        ('PUT', '/api/tasks/task_1') => {
          'task': {
            'id': 'task_1',
            'account_id': request.uri.queryParameters['account_id'],
            'agent': 'Hermes',
            'name': body?['name'],
            'schedule': body?['schedule'],
            'prompt': body?['prompt'],
            'enabled': body?['enabled'],
            'status': 'active',
            'skills': body?['skills'] ?? [],
          },
        },
        ('PUT', '/api/tasks/task_1/enabled') => {
          'task': {
            'id': 'task_1',
            'account_id': request.uri.queryParameters['account_id'],
            'agent': 'Hermes',
            'name': 'Daily',
            'schedule': '0 9 * * *',
            'prompt': 'Summarize',
            'enabled': body?['enabled'],
            'status': body?['enabled'] == true ? 'active' : 'paused',
          },
        },
        ('POST', '/api/tasks/task_1/run') => {
          'run': {
            'id': 'run_1',
            'task_id': 'task_1',
            'started_at': '2026-04-24T09:00:00Z',
            'status': 'running',
          },
        },
        ('GET', '/api/tasks/task_1/runs') => {
          'runs': [
            {
              'id': 'run_1',
              'task_id': 'task_1',
              'started_at': '2026-04-24T09:00:00Z',
              'status': 'success',
              'output_preview': 'done',
            },
          ],
        },
        ('GET', '/api/tasks/task_1/runs/run_1/output') => {
          'output': 'full output',
        },
        ('DELETE', '/api/tasks/task_1') => {'ok': true},
        _ => {'error': 'not_found'},
      };

      request.response
        ..statusCode = response.containsKey('error') ? 404 : 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(response));
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('TasksApiService serializes task lifecycle HTTP calls', () async {
    final api = TasksApiService();
    const draft = TaskDraft(
      accountId: 'hermes',
      name: 'Daily',
      schedule: '0 9 * * *',
      prompt: 'Summarize',
      skills: ['notes'],
      deliver: 'local',
    );

    final tasks = await api.listTasks(accountId: 'hermes');
    final created = await api.createTask(draft);
    final updated = await api.updateTask('task_1', draft);
    final toggled = await api.setEnabled('task_1', 'hermes', false);
    final run = await api.runTask('task_1', 'hermes');
    final runs = await api.listRuns('task_1', 'hermes');
    final output = await api.getRunOutput('task_1', 'run_1', 'hermes');
    await api.deleteTask('task_1', 'hermes');

    expect(tasks.single.accountId, 'hermes');
    expect(created.id, 'task_new');
    expect(updated.name, 'Daily');
    expect(toggled?.enabled, false);
    expect(run?.status, 'running');
    expect(runs.single.outputPreview, 'done');
    expect(output, 'full output');

    expect(requests[0].method, 'GET');
    expect(requests[0].uri.path, '/api/tasks');
    expect(requests[0].uri.queryParameters['account_id'], 'hermes');
    expect(requests[1].method, 'POST');
    expect(requests[1].body?['account_id'], 'hermes');
    expect(requests[1].body?['skills'], ['notes']);
    expect(requests[2].method, 'PUT');
    expect(requests[2].uri.path, '/api/tasks/task_1');
    expect(requests[2].body?.containsKey('account_id'), false);
    expect(requests[3].uri.path, '/api/tasks/task_1/enabled');
    expect(requests[3].body?['enabled'], false);
    expect(requests[4].uri.path, '/api/tasks/task_1/run');
    expect(requests[5].uri.path, '/api/tasks/task_1/runs');
    expect(requests[6].uri.path, '/api/tasks/task_1/runs/run_1/output');
    expect(requests[7].method, 'DELETE');
  });
}
