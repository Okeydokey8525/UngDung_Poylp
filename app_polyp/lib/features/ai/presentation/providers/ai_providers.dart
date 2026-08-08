import 'package:app_polyp/core/config/ai_service_config.dart';
import 'package:app_polyp/core/network/ai_request_id.dart';
import 'package:app_polyp/core/network/direct_ai_client.dart';
import 'package:app_polyp/features/ai/data/ai_repository.dart';
import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final aiServiceConfigProvider = Provider<AiServiceConfig>(
  (ref) => AiServiceConfig.fromEnvironment(),
);

final aiRequestIdGeneratorProvider = Provider<AiRequestIdGenerator>(
  (ref) => AiRequestIdGenerator(),
);

final directAiDioProvider = Provider<Dio>((ref) {
  final config = ref.watch(aiServiceConfigProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      headers: const {Headers.acceptHeader: 'application/json'},
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

final directAiClientProvider = Provider<DirectAiClient>(
  (ref) => DirectAiClient(
    ref.watch(directAiDioProvider),
    ref.watch(aiRequestIdGeneratorProvider),
  ),
);

final directAiRepositoryProvider = Provider<AiRepository>(
  (ref) => DirectAiRepository(ref.watch(directAiClientProvider)),
);

final aiHealthProvider = FutureProvider<AiHealthResponse>(
  (ref) => ref.watch(directAiRepositoryProvider).getHealth(),
  retry: (retryCount, error) => null,
);

final aiModelsProvider = FutureProvider<AiModelsResponse>(
  (ref) => ref.watch(directAiRepositoryProvider).getModels(),
  retry: (retryCount, error) => null,
);
