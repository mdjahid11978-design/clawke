import 'dart:async';

import 'package:client/data/repositories/conversation_repository.dart';
import 'package:client/data/repositories/model_cache_repository.dart';
import 'package:client/data/repositories/skill_cache_repository.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:client/models/gateway_model.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/screens/conversation_settings_sheet.dart';
import 'package:client/services/config_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'conversation settings shows cached model in picker before sync completes',
    (tester) async {
      final modelRepo = _FakeModelCacheRepository(
        cached: [_cachedModel('cached-model')],
        syncCompleter: Completer<List<CachedGatewayModel>>(),
      );

      await _pumpSheet(tester, modelRepo: modelRepo);
      await tester.tap(find.byIcon(Icons.layers_rounded));
      await tester.pumpAndSettle();

      expect(find.text('cached-model'), findsOneWidget);
    },
  );

  testWidgets(
    'conversation settings shows cached enabled skill in picker before sync completes',
    (tester) async {
      final skillRepo = _FakeSkillCacheRepository(
        cached: [_skill(name: 'weather', description: 'Weather lookup')],
        syncCompleter: Completer<List<ManagedSkill>>(),
      );

      await _pumpSheet(tester, skillRepo: skillRepo);
      await tester.tap(find.byIcon(Icons.build_rounded));
      await tester.pumpAndSettle();

      expect(find.text('weather'), findsOneWidget);
      expect(find.text('Weather lookup'), findsOneWidget);
    },
  );

  testWidgets(
    'conversation settings does not add selected stale model to picker',
    (tester) async {
      await _pumpSheet(
        tester,
        conversationId: 'conv-1',
        modelRepo: _FakeModelCacheRepository(
          cached: [_cachedModel('fresh-model')],
          syncModels: [_cachedModel('fresh-model')],
        ),
        configApi: _FakeConfigApiService(
          config: const ConvConfig(convId: 'conv-1', modelId: 'old-model'),
        ),
      );

      expect(find.text('old-model'), findsOneWidget);

      await tester.tap(find.text('old-model'));
      await tester.pumpAndSettle();

      expect(find.text('old-model'), findsNothing);
      expect(find.text('fresh-model'), findsOneWidget);
    },
  );

  testWidgets(
    'model picker preserves raw duplicate display names without stale selected alias',
    (tester) async {
      await _pumpSheet(
        tester,
        conversationId: 'conv-1',
        modelRepo: _FakeModelCacheRepository(
          cached: [
            _cachedModel(
              'custom/deepseek-v4-pro',
              displayName: 'deepseek-v4-pro',
              provider: 'custom',
            ),
            _cachedModel(
              'deepseek-v4-pro/deepseek-v4-pro',
              displayName: 'deepseek-v4-pro',
              provider: 'deepseek-v4-pro',
            ),
            _cachedModel(
              'openai/gpt-4o',
              displayName: 'gpt-4o',
              provider: 'openai',
            ),
          ],
        ),
        configApi: _FakeConfigApiService(
          config: const ConvConfig(
            convId: 'conv-1',
            modelId: 'deepseek-v4-pro',
          ),
        ),
      );

      await tester.tap(find.text('deepseek-v4-pro'));
      await tester.pumpAndSettle();

      expect(find.text('deepseek-v4-pro'), findsNWidgets(2));
    },
  );

  testWidgets(
    'conversation settings keeps selected stale skill visible with stale label',
    (tester) async {
      await _pumpSheet(
        tester,
        conversationId: 'conv-1',
        skillRepo: _FakeSkillCacheRepository(
          cached: [_skill(name: 'fresh-skill')],
          syncSkills: [_skill(name: 'fresh-skill')],
        ),
        configApi: _FakeConfigApiService(
          config: const ConvConfig(
            convId: 'conv-1',
            skills: ['old-skill'],
            skillMode: 'priority',
          ),
        ),
      );

      expect(find.text('old-skill'), findsOneWidget);
      expect(find.text('已失效'), findsOneWidget);
    },
  );

  testWidgets('model picker refresh triggers repository sync', (tester) async {
    final modelRepo = _FakeModelCacheRepository(
      cached: [_cachedModel('cached-model')],
      syncModels: [_cachedModel('refreshed-model')],
    );

    await _pumpSheet(tester, modelRepo: modelRepo);
    expect(modelRepo.syncCalls, 1);

    await tester.tap(find.byIcon(Icons.layers_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();

    expect(modelRepo.syncCalls, 2);
    expect(find.text('refreshed-model'), findsOneWidget);
  });

  testWidgets('conversation settings saves selected model provider', (
    tester,
  ) async {
    final configApi = _FakeConfigApiService();

    await _pumpSheet(
      tester,
      modelRepo: _FakeModelCacheRepository(
        cached: [
          _cachedModel(
            'anthropic/claude-sonnet-4',
            displayName: 'Claude Sonnet 4',
            provider: 'anthropic',
          ),
        ],
      ),
      configApi: configApi,
    );

    await tester.tap(find.byIcon(Icons.layers_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude Sonnet 4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(configApi.savedConfig?.modelId, 'anthropic/claude-sonnet-4');
    expect(configApi.savedConfig?.modelProvider, 'anthropic');
  });

  testWidgets('skill picker refresh triggers repository sync', (tester) async {
    final skillRepo = _FakeSkillCacheRepository(
      cached: [_skill(name: 'cached-skill')],
      syncSkills: [_skill(name: 'refreshed-skill')],
    );

    await _pumpSheet(tester, skillRepo: skillRepo);
    expect(skillRepo.syncCalls, 1);

    await tester.tap(find.byIcon(Icons.build_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();

    expect(skillRepo.syncCalls, 2);
    expect(find.text('refreshed-skill'), findsOneWidget);
  });

  testWidgets('skill picker search filters available skills', (tester) async {
    final skillRepo = _FakeSkillCacheRepository(
      cached: [
        _skill(name: 'weather', description: 'Weather lookup'),
        _skill(name: 'calendar', description: 'Calendar helper'),
      ],
    );

    await _pumpSheet(tester, skillRepo: skillRepo);
    await tester.tap(find.byIcon(Icons.build_rounded));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'calendar');
    await tester.pump();

    expect(find.text('Calendar helper'), findsOneWidget);
    expect(find.text('weather'), findsNothing);
  });

  testWidgets(
    'skill picker keeps search usable when opened before sync finishes',
    (tester) async {
      final syncCompleter = Completer<List<ManagedSkill>>();
      final skillRepo = _FakeSkillCacheRepository(syncCompleter: syncCompleter);

      await _pumpSheet(tester, skillRepo: skillRepo);
      await tester.tap(find.byIcon(Icons.build_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);

      syncCompleter.complete([
        _skill(name: 'weather', description: 'Weather lookup'),
        _skill(name: 'calendar', description: 'Calendar helper'),
      ]);
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'calendar');
      await tester.pump();

      expect(find.text('Calendar helper'), findsOneWidget);
      expect(find.text('weather'), findsNothing);
    },
  );
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  String? conversationId,
  _FakeModelCacheRepository? modelRepo,
  _FakeSkillCacheRepository? skillRepo,
  _FakeConfigApiService? configApi,
  _FakeConversationRepository? conversationRepo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        modelCacheRepositoryProvider.overrideWithValue(
          modelRepo ?? _FakeModelCacheRepository(),
        ),
        skillCacheRepositoryProvider.overrideWithValue(
          skillRepo ?? _FakeSkillCacheRepository(),
        ),
        configApiServiceProvider.overrideWithValue(
          configApi ?? _FakeConfigApiService(),
        ),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepo ?? _FakeConversationRepository(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: ConversationSettingsSheet(
          conversationId: conversationId,
          accountId: 'hermes',
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

const _defaultCachedAt = 123;

CachedGatewayModel _cachedModel(
  String modelId, {
  String? displayName,
  String? provider,
}) {
  return CachedGatewayModel(
    modelId: modelId,
    displayName: displayName ?? modelId,
    provider: provider,
    updatedAt: _defaultCachedAt,
    lastSeenAt: _defaultCachedAt,
  );
}

ManagedSkill _skill({
  required String name,
  String description = '',
  bool enabled = true,
}) {
  return ManagedSkill(
    id: name,
    name: name,
    description: description,
    category: 'general',
    enabled: enabled,
    source: 'gateway',
    sourceLabel: 'Gateway',
    writable: false,
    deletable: false,
    path: '',
    root: '',
    updatedAt: 0,
    hasConflict: false,
  );
}

class _FakeModelCacheRepository implements ModelCacheRepository {
  _FakeModelCacheRepository({
    List<CachedGatewayModel> cached = const [],
    List<CachedGatewayModel>? syncModels,
    Completer<List<CachedGatewayModel>>? syncCompleter,
  }) : _cached = cached,
       _syncModels = syncModels,
       _syncCompleter = syncCompleter;

  List<CachedGatewayModel> _cached;
  final List<CachedGatewayModel>? _syncModels;
  final Completer<List<CachedGatewayModel>>? _syncCompleter;
  int syncCalls = 0;

  @override
  Future<List<CachedGatewayModel>> getModels(String gatewayId) async => _cached;

  @override
  Future<List<CachedGatewayModel>> syncGateway(String gatewayId) async {
    syncCalls += 1;
    final models = _syncCompleter == null
        ? (_syncModels ?? _cached)
        : await _syncCompleter.future;
    _cached = models;
    return models;
  }

  @override
  Stream<List<CachedGatewayModel>> watchModels(String gatewayId) {
    return Stream.value(_cached);
  }
}

class _FakeSkillCacheRepository implements SkillCacheRepository {
  _FakeSkillCacheRepository({
    List<ManagedSkill> cached = const [],
    List<ManagedSkill>? syncSkills,
    Completer<List<ManagedSkill>>? syncCompleter,
  }) : _cached = cached,
       _syncSkills = syncSkills,
       _syncCompleter = syncCompleter;

  List<ManagedSkill> _cached;
  final List<ManagedSkill>? _syncSkills;
  final Completer<List<ManagedSkill>>? _syncCompleter;
  int syncCalls = 0;

  @override
  Future<List<ManagedSkill>> getSkills(String gatewayId, String locale) async {
    return _cached;
  }

  @override
  Future<List<ManagedSkill>> syncGateway(
    SkillScope scope,
    String locale,
  ) async {
    syncCalls += 1;
    final skills = _syncCompleter == null
        ? (_syncSkills ?? _cached)
        : await _syncCompleter.future;
    _cached = skills;
    return skills;
  }

  @override
  Stream<List<ManagedSkill>> watchSkills(String gatewayId, String locale) {
    return Stream.value(_cached);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeConfigApiService implements ConfigApiService {
  _FakeConfigApiService({this.config = const ConvConfig(convId: 'conv-1')});

  final ConvConfig config;
  String? savedConvId;
  ConvConfig? savedConfig;

  @override
  Future<ConvConfig> getConvConfig(String convId) async => config;

  @override
  Future<bool> saveConvConfig(String convId, ConvConfig config) async {
    savedConvId = convId;
    savedConfig = config;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeConversationRepository implements ConversationRepository {
  @override
  Future<String> createConversation({
    required String accountId,
    required String type,
    String? conversationId,
    String? name,
    String? iconUrl,
  }) async {
    return conversationId ?? 'conv-created';
  }

  @override
  Future<String?> getConversationName(String conversationId) async => 'Chat';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
