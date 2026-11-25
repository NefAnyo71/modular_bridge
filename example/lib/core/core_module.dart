import 'dart:async';

import 'package:modular_bridge/modular_bridge.dart';

/// Simple network client whose configuration is decoded from [BridgeConfig].
class ApiClient {
  ApiClient({required this.baseUrl, required this.timeout});

  final String baseUrl;
  final Duration timeout;

  Future<String> get(String endpoint) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return 'Response from $baseUrl$endpoint (timeout: ${timeout.inSeconds}s)';
  }
}

/// Decodes the `api` config section (`{"baseUrl": ..., "timeoutMs": ...}`)
/// into an [ApiClient]. Shared by the config binding so every rebuild
/// produces an identically shaped client.
ApiClient decodeApiClient(dynamic value) {
  final map = value is Map ? value : const {};
  return ApiClient(
    baseUrl: map['baseUrl'] as String? ?? 'https://localhost',
    timeout: Duration(milliseconds: map['timeoutMs'] as int? ?? 5000),
  );
}

/// Async resource simulating a remote database/session connection.
///
/// Registered with a [BridgeRetryPolicy] so transient startup failures are
/// retried with backoff instead of failing the whole container.
class SessionStore {
  SessionStore({required this.endpoint});

  final String endpoint;
  bool _connected = false;

  bool get isConnected => _connected;

  Future<void> connect() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _connected = true;
  }

  Future<void> close() async {
    _connected = false;
  }
}

/// Core logging service.
class LoggingService {
  void log(String message) {
    // ignore: avoid_print
    print('[ModularBridge] $message');
  }
}

/// The [CoreModule] provides low-level infrastructure services needed by
/// feature modules.
///
/// Showcases:
/// - [registerConfigBinding]: `ApiClient` re-decodes automatically whenever
///   the effective config changes (environment hot-switch, `set`, `remove`).
/// - [registerAsyncSingleton] + [BridgeRetryPolicy] + `eager: true`: the
///   session store connects during `warmup()`/`allReady` with retries.
final class CoreModule extends FeatureModule {
  @override
  String get name => 'CoreModule';

  @override
  void registerDependencies(ModularBridge bridge) {
    bridge.registerSingleton<LoggingService>(LoggingService());

    bridge.registerConfigBinding<ApiClient>(
      configKey: 'api',
      decoder: decodeApiClient,
      onDispose: (_) {},
    );

    bridge.registerAsyncSingleton<SessionStore>(
      () async {
        final api = bridge.config.getMap('api');
        final store = SessionStore(endpoint: '${api['baseUrl']}/session');
        await store.connect();
        return store;
      },
      eager: true,
      retryPolicy: const BridgeRetryPolicy(
        maxAttempts: 3,
        delay: Duration(milliseconds: 100),
        backoff: 2.0,
      ),
      onDispose: (store) => store.close(),
    );
  }

  @override
  FutureOr<void> warmup(ModularBridge bridge) {
    // Runs after CoreModule's owned registrations resolved — a good place
    // for non-dependency startup work.
    bridge.get<LoggingService>().log('CoreModule warmup complete');
  }
}
