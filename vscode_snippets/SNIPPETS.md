# Modular Bridge Snippets — Full Reference

Every snippet ships with `prefix: mb_*` and `scope: dart` — type the prefix
in any Dart file and press `Tab` (or `Enter`) to expand.

## Placeholder syntax

| Syntax | Meaning |
| --- | --- |
| `${1:Name}` | First tab stop — inserted with `Name` pre-selected; typing replaces it. Repeated `${1}` occurrences mirror each other. |
| `${2}`, `${3}` ... | Subsequent tab stops, visited in order with `Tab`. |
| `${1|a,b,c|}` | Choice list — `Tab`/arrow keys pick an option. |
| `$0` | Final cursor position (implicit end of snippet). |

> Snippets insert text at the cursor only — they never add imports
> automatically. Use `Ctrl+.` → **Add import** for missing imports.

## Curated templates


## Public API call snippets

### `mb_addEventInterceptor` — Call addEventInterceptor(BridgeEventInterceptor interceptor)

```dart
bridge.eventBus.addEventInterceptor(${1:interceptor})
```

### `mb_addResolutionInterceptor` — Call addResolutionInterceptor(BridgeResolutionInterceptor interceptor)

```dart
bridge.addResolutionInterceptor(${1:interceptor})
```

### `mb_allReadySync` — Call allReadySync({bool ignorePendingAsyncCreation = false})

```dart
bridge.allReadySync()
```

### `mb_allready` — Await all readiness-tracked dependencies

```dart
await bridge.allReady(timeout: const Duration(seconds: ${1:10}));
```

### `mb_assertAllReadySync` — Call assertAllReadySync

```dart
bridge.assertAllReadySync()
```

### `mb_assertNoLeaks` — Call assertNoLeaks

```dart
bridge.assertNoLeaks()
```

### `mb_assertRegistered` — Call assertRegistered({String? instanceName})

```dart
bridge.assertRegistered<T>()
```

### `mb_asyncSingleton` — Call asyncSingleton(Future<T> Function() factory, { String? instanceName, bool override = false, void Funct...)

```dart
bridge.asyncSingleton<T>(${1:factory})
```

### `mb_bind` — Call bind({ required String configKey, required T Function(dynamic value) decoder, dynamic defaul...)

```dart
bridge.bind<T>(configKey: ${1:configKey}, decoder: ${2:decoder})
```

### `mb_call` — Call call({String? instanceName})

```dart
bridge.call<T>()
```

### `mb_callAsync` — Call callAsync({String? instanceName})

```dart
bridge.callAsync<T>()
```

### `mb_cancel` — Call cancel

```dart
subscription.cancel()
```

### `mb_cancelSubscriptionsForOwner` — Call cancelSubscriptionsForOwner(String ownerId)

```dart
bridge.eventBus.cancelSubscriptionsForOwner(${1:ownerId})
```

### `mb_checkModuleHealth` — Call checkModuleHealth

```dart
bridge.checkModuleHealth()
```

### `mb_checkScopeNameAvailable` — Call checkScopeNameAvailable(String? scopeName)

```dart
bridge.checkScopeNameAvailable(${1:scopeName})
```

### `mb_clearEventInterceptors` — Call clearEventInterceptors

```dart
bridge.eventBus.clearEventInterceptors()
```

### `mb_clearReplayHistory` — Call clearReplayHistory

```dart
bridge.eventBus.clearReplayHistory()
```

### `mb_clearResolutionInterceptors` — Call clearResolutionInterceptors

```dart
bridge.clearResolutionInterceptors()
```

### `mb_clearSubscriptions` — Call clearSubscriptions

```dart
bridge.eventBus.clearSubscriptions()
```

### `mb_config` — BridgeConfig — environments + common values

```dart
final config = BridgeConfig(
  environment: BridgeEnvironment.${1|dev,staging,prod|},
  commonValues: {
    '${2:appName}': '${3:MyApp}',
  },
  environmentValues: {
    BridgeEnvironment.dev: {
      '${4:apiBaseUrl}': 'http://localhost:8080',
    },
    BridgeEnvironment.staging: {
      '${4:apiBaseUrl}': 'https://staging.example.com',
    },
    BridgeEnvironment.prod: {
      '${4:apiBaseUrl}': 'https://api.example.com',
    },
  },
);

ModularBridge.I.setConfig(config);
```

### `mb_configValue` — Call configValue(String key, {T? defaultValue})

```dart
bridge.configValue<T>(${1:key})
```

### `mb_config_binding` — registerConfigBinding — dependency rebuilt on config change

```dart
bridge.registerConfigBinding<${1:AppConfig}>(
  configKey: '${2:api}',
  decoder: (value) => ${1:AppConfig}.fromMap(value as Map<String, dynamic>),
);
```

### `mb_config_env` — BridgeConfig from a .env file (pure Dart loader)

```dart
final config = await BridgeConfig.fromEnvFile(
  'assets/.env',
  loader: (path) => File(path).readAsString(),
);
```

### `mb_config_get` — Typed config read with default

```dart
final ${1:String} ${2:value} = config.get${3|String,int,double,bool,Duration,Uri|}('${4:key}'${5:, defaultValue: ${6:null}});
```

### `mb_config_json` — BridgeConfig from a JSON asset/string

```dart
final config = await BridgeConfig.fromAsset(
  'assets/config.json',
  loader: (path) => File(path).readAsString(),
);
```

### `mb_config_switch` — Hot-switch the active environment at runtime

```dart
config.switchEnvironment(BridgeEnvironment.${1|dev,staging,prod|});
```

### `mb_createChildScope` — Call createChildScope({String? scopeName})

```dart
scope.createChildScope()
```

### `mb_createIsolated` — Call ModularBridge.createIsolated({ BridgeConfig? config, BridgeEventBus? eventBus, })

```dart
ModularBridge.createIsolated()
```

### `mb_createScope` — Call createScope({String? scopeName})

```dart
bridge.createScope()
```

### `mb_createScopeAsync` — Call createScopeAsync([ FutureOr<void> Function(BridgeScope scope)? init, ])

```dart
bridge.createScopeAsync()
```

### `mb_debugLeakReport` — Call debugLeakReport

```dart
bridge.debugLeakReport()
```

### `mb_dep` — dep<T>() — DependencyKey shorthand for dependsOn lists

```dart
dep<${1:Service}>()
```

### `mb_dep_named` — dep<T>('name') — named DependencyKey shorthand

```dart
dep<${1:Service}>('${2:name}')
```

### `mb_dependenciesOf` — Call dependenciesOf(DependencyInfo info)

```dart
bridge.dependencyGraph().dependenciesOf(${1:info})
```

### `mb_dependencyEventHistory` — Call dependencyEventHistory({int count = 50})

```dart
bridge.dependencyEventHistory()
```

### `mb_dependencyGraph` — Call dependencyGraph

```dart
bridge.dependencyGraph()
```

### `mb_depthOf` — Call depthOf(FeatureModule module)

```dart
bridge.depthOf(${1:module})
```

### `mb_diagnosticsReport` — Call diagnosticsReport

```dart
bridge.diagnosticsReport()
```

### `mb_dropScope` — Call dropScope(String scopeName)

```dart
bridge.dropScope(${1:scopeName})
```

### `mb_enableDevTools` — Call enableDevTools

```dart
bridge.enableDevTools()
```

### `mb_event` — BridgeEvent — immutable domain event

```dart
final class ${1:SomethingHappened}Event extends BridgeEvent {
  const ${1:SomethingHappened}Event({required this.${2:field}});

  final ${3:String} ${2:field};
}
```

### `mb_event_once` — Wait for the next event of type T

```dart
final event = await bridge.eventBus.once<${1:MyEvent}>(timeout: const Duration(seconds: ${2:5}));
```

### `mb_event_onlatest` — Stream that replays the latest event then continues live

```dart
bridge.eventBus.onLatest<${1:MyEvent}>().listen((event) {
  ${2}
});
```

### `mb_event_publish` — Publish an event on the bridge event bus

```dart
bridge.publish(${1:MyEvent()});
```

### `mb_event_subscribe` — Subscribe to an event (managed BridgeSubscription)

```dart
final sub = bridge.eventBus.subscribe<${1:MyEvent}>(${2:(event) {
    ${3}
  }}, ownerId: '${4:owner}');
```

### `mb_findDescriptorFromRoot` — Call findDescriptorFromRoot(DependencyKey key)

```dart
bridge.findDescriptorFromRoot(${1:key})
```

### `mb_findScope` — Call findScope(String scopeName)

```dart
bridge.findScope(${1:scopeName})
```

### `mb_fn_parseEnvFile` — Call parseEnvFile(String source)

```dart
parseEnvFile(${1:source})
```

### `mb_fn_reportBridgeError` — Call reportBridgeError(
  Object error,
  StackTrace stackTrace, {
  String library = 'modular_bridge',
  String? context,
})

```dart
reportBridgeError(${1:error}, ${2:stackTrace})
```

### `mb_fromAsset` — Call fromAsset(String assetPath, { required Future<String> Function(String path) loader, BridgeEnviron...)

```dart
BridgeConfig.fromAsset(${1:assetPath}, loader: ${2:loader})
```

### `mb_fromDescriptor` — Call DependencyInfo.fromDescriptor(DependencyDescriptor<dynamic> d)

```dart
DependencyInfo.fromDescriptor(${1:d})
```

### `mb_fromEnvFile` — Call fromEnvFile(String path, { required Future<String> Function(String path) loader, BridgeEnvironment?...)

```dart
BridgeConfig.fromEnvFile(${1:path}, loader: ${2:loader})
```

### `mb_fromEnvString` — Call BridgeConfig.fromEnvString(String source, { BridgeEnvironment? environment, List<String> environmentKeys = envEnvi...)

```dart
BridgeConfig.fromEnvString(${1:source})
```

### `mb_fromJson` — Call BridgeConfig.fromJson(Map<String, dynamic> json, { BridgeEnvironment? environment, })

```dart
BridgeConfig.fromJson(${1:json})
```

### `mb_fromString` — Call BridgeConfig.fromString(String source, { BridgeEnvironment? environment, })

```dart
BridgeConfig.fromString(${1:source})
```

### `mb_get` — Resolve a dependency synchronously

```dart
final ${1:Service} ${2:service} = bridge.get<${1:Service}>${3|, instanceName: 'name'|}();
```

### `mb_getAllAsync` — Call getAllAsync

```dart
bridge.getAllAsync<T>()
```

### `mb_getBool` — Call getBool(String key, {bool? defaultValue})

```dart
config.getBool(${1:key})
```

### `mb_getDouble` — Call getDouble(String key, {double? defaultValue})

```dart
config.getDouble(${1:key})
```

### `mb_getDuration` — Call getDuration(String key, {Duration? defaultValue})

```dart
config.getDuration(${1:key})
```

### `mb_getInt` — Call getInt(String key, {int? defaultValue})

```dart
config.getInt(${1:key})
```

### `mb_getMap` — Call getMap(String key, {Map<String, dynamic>? defaultValue})

```dart
config.getMap(${1:key})
```

### `mb_getModule` — Call getModule

```dart
bridge.getModule<M>()
```

### `mb_getParam` — Call getParam({ required P1 param1, required P2 param2, String? instanceName, })

```dart
bridge.getParam<T, P1, P2>(param1: ${1:param1}, param2: ${2:param2})
```

### `mb_getParamAsync` — Call getParamAsync({ required P1 param1, required P2 param2, String? instanceName, })

```dart
bridge.getParamAsync<T, P1, P2>(param1: ${1:param1}, param2: ${2:param2})
```

### `mb_getSection` — Call getSection(String key, T Function(Map<String, dynamic> values) decoder,)

```dart
config.getSection<T>(${1:key}, ${2:decoder})
```

### `mb_getString` — Call getString(String key, {String? defaultValue})

```dart
config.getString(${1:key})
```

### `mb_getUri` — Call getUri(String key, {Uri? defaultValue})

```dart
config.getUri(${1:key})
```

### `mb_get_activeModuleNames` — Access activeModuleNames

```dart
bridge.activeModuleNames
```

### `mb_get_activeScopeNames` — Access activeScopeNames

```dart
bridge.activeScopeNames
```

### `mb_get_activeSubscriptionCount` — Access activeSubscriptionCount

```dart
bridge.eventBus.activeSubscriptionCount
```

### `mb_get_averageMicros` — Access averageMicros

```dart
bridge.metrics.averageMicros
```

### `mb_get_cacheHitRatio` — Access cacheHitRatio

```dart
bridge.metrics.cacheHitRatio
```

### `mb_get_configOverrides` — Access configOverrides

```dart
scope.configOverrides
```

### `mb_get_currentScope` — Access currentScope

```dart
bridge.currentScope
```

### `mb_get_currentScopeName` — Access currentScopeName

```dart
bridge.currentScopeName
```

### `mb_get_currentValues` — Access currentValues

```dart
config.currentValues
```

### `mb_get_dependencyInfo` — Access dependencyInfo

```dart
bridge.dependencyInfo
```

### `mb_get_entries` — Access entries

```dart
bridge.metrics.entries
```

### `mb_get_environment` — Access environment

```dart
config.environment
```

### `mb_get_eventBus` — Access eventBus

```dart
bridge.eventBus
```

### `mb_get_eventInterceptors` — Access eventInterceptors

```dart
bridge.eventBus.eventInterceptors
```

### `mb_get_hasCycles` — Access hasCycles

```dart
bridge.dependencyGraph().hasCycles
```

### `mb_get_instance` — Access instance

```dart
ModularBridge.instance
```

### `mb_get_isCanceled` — Access isCanceled

```dart
subscription.isCanceled
```

### `mb_get_isDev` — Access isDev

```dart
environment.isDev
```

### `mb_get_isDisposed` — Access isDisposed

```dart
bridge.isDisposed
```

### `mb_get_isFinal` — Access isFinal

```dart
scope.isFinal
```

### `mb_get_isHealthy` — Access isHealthy

```dart
bridge.diagnosticsReport().isHealthy
```

### `mb_get_isPaused` — Access isPaused

```dart
subscription.isPaused
```

### `mb_get_isProd` — Access isProd

```dart
environment.isProd
```

### `mb_get_isStaging` — Access isStaging

```dart
environment.isStaging
```

### `mb_get_moduleEntries` — Access moduleEntries

```dart
bridge.metrics.moduleEntries
```

### `mb_get_onChanged` — Access onChanged

```dart
config.onChanged
```

### `mb_get_onConfigChanged` — Access onConfigChanged

```dart
bridge.onConfigChanged
```

### `mb_get_onDependencyEvents` — Access onDependencyEvents

```dart
bridge.onDependencyEvents
```

### `mb_get_onEnvironmentChanged` — Access onEnvironmentChanged

```dart
config.onEnvironmentChanged
```

### `mb_get_parentScope` — Access parentScope

```dart
scope.parentScope
```

### `mb_get_pendingReadinessKeys` — Access pendingReadinessKeys

```dart
bridge.pendingReadinessKeys
```

### `mb_get_publishCounts` — Access publishCounts

```dart
bridge.eventBus.publishCounts
```

### `mb_get_registeredDependencies` — Access registeredDependencies

```dart
bridge.registeredDependencies
```

### `mb_get_resolutionInterceptors` — Access resolutionInterceptors

```dart
bridge.resolutionInterceptors
```

### `mb_get_totalCacheHits` — Access totalCacheHits

```dart
bridge.metrics.totalCacheHits
```

### `mb_get_totalFailures` — Access totalFailures

```dart
bridge.metrics.totalFailures
```

### `mb_get_totalPublished` — Access totalPublished

```dart
bridge.eventBus.totalPublished
```

### `mb_get_totalResolutions` — Access totalResolutions

```dart
bridge.metrics.totalResolutions
```

### `mb_get_value` — Access value

```dart
lazy.value
```

### `mb_getall` — Resolve every registration of type T (incl. named)

```dart
final all = bridge.getAll<${1:Service}>();
```

### `mb_getasync` — Resolve a dependency asynchronously

```dart
final ${1:Service} ${2:service} = await bridge.getAsync<${1:Service}>();
```

### `mb_hasConfigOverride` — Call hasConfigOverride(String key)

```dart
scope.hasConfigOverride(${1:key})
```

### `mb_hasKey` — Call hasKey(String key)

```dart
config.hasKey(${1:key})
```

### `mb_hasListeners` — Call hasListeners

```dart
bridge.hasListeners<T>()
```

### `mb_hasLocal` — Call hasLocal(DependencyKey key)

```dart
scope.hasLocal(${1:key})
```

### `mb_healthcheck` — Run health checks on all registered modules

```dart
final results = await bridge.checkModuleHealth();
for (final r in results.where((r) => !r.isHealthy)) {
  reportBridgeError(r.error ?? StateError('unhealthy'), StackTrace.current,
    context: 'Module \${r.moduleName} unhealthy');
}
```

### `mb_history` — Call history

```dart
bridge.history<T>()
```

### `mb_interceptor` — Resolution interceptor — timing/logging around get<T>()

```dart
bridge.addResolutionInterceptor(
  (request, next) {
    final sw = Stopwatch()..start();
    developer.log('Resolving \${request.type}', name: 'modular_bridge');
    final result = next();
    developer.log('Resolved in \${sw.elapsedMilliseconds}ms', name: 'modular_bridge');
    return result;
  },
);
```

### `mb_isModuleRegistered` — Call isModuleRegistered

```dart
bridge.isModuleRegistered<M>()
```

### `mb_isReady` — Call isReady({ String? instanceName, Duration? timeout, })

```dart
bridge.isReady<T>()
```

### `mb_isReadySync` — Call isReadySync({String? instanceName})

```dart
bridge.isReadySync<T>()
```

### `mb_isRegistered` — Call isRegistered({String? instanceName})

```dart
bridge.isRegistered<T>()
```

### `mb_isRegisteredFromRoot` — Call isRegisteredFromRoot({String? instanceName})

```dart
bridge.isRegisteredFromRoot<T>()
```

### `mb_isScopeActive` — Call isScopeActive(String scopeName)

```dart
bridge.isScopeActive(${1:scopeName})
```

### `mb_isolated` — Create an isolated bridge for tests

```dart
final bridge = ModularBridge.createIsolated(
  config: BridgeConfig(environment: BridgeEnvironment.dev),
);
```

### `mb_lastEvent` — Call lastEvent

```dart
bridge.lastEvent<T>()
```

### `mb_lazy` — Lazy<T> — deferred dependency for circular deps

```dart
final lazy = bridge.lazy<${1:Service}>();
final value = lazy.value; // or: await lazy.resolveAsync()
```

### `mb_lazySingleton` — Call lazySingleton(T Function() factory, { String? instanceName, bool override = false, void Function(T in...)

```dart
bridge.lazySingleton<T>(${1:factory})
```

### `mb_lazy_scoped` — Lazy<T> bound to a BridgeScope hierarchy

```dart
final lazy = scope.lazy<${1:Service}>();
final value = lazy.value;
```

### `mb_logging` — Call logging({ void Function(String message)? log, })

```dart
BridgeInterceptors.logging()
```

### `mb_module` — FeatureModule — full module skeleton

```dart
final class ${1:FeatureName}Module extends FeatureModule {
  @override
  String get name => '${1:feature}';

  @override
  List<Type> get dependencies => const [${2:CoreModule}];

  @override
  List<BridgeEnvironment>? get environments => null;

  @override
  FutureOr<void> registerDependencies(ModularBridge bridge) async {
    ${3}
  }

  @override
  FutureOr<void> init(ModularBridge bridge) {
    ${4}
  }

  @override
  FutureOr<bool> healthCheck(ModularBridge bridge) async {
    return true;
  }
}
```

### `mb_moduleDependents` — Call moduleDependents(Type moduleType)

```dart
bridge.moduleDependents(${1:moduleType})
```

### `mb_module_core` — CoreModule — base services module skeleton

```dart
final class CoreModule extends FeatureModule {
  @override
  String get name => 'CoreModule';

  @override
  FutureOr<void> registerDependencies(ModularBridge bridge) async {
    bridge.registerLazySingleton<${1:AuthService}>(() => ${1:AuthService}());
  }
}
```

### `mb_module_dispose` — FeatureModule.dispose — teardown hook

```dart
@override
@mustCallSuper()
FutureOr<void> dispose(ModularBridge bridge) async {
  ${1}
  await super.dispose(bridge);
}
```

### `mb_module_environments` — FeatureModule.environments — env allow-list

```dart
@override
List<BridgeEnvironment>? get environments =>
    const [BridgeEnvironment.dev, BridgeEnvironment.staging];
```

### `mb_module_healthcheck` — FeatureModule.healthCheck — module health probe

```dart
@override
Future<bool> healthCheck(ModularBridge bridge) async {
  ${1:return true;}
}
```

### `mb_module_registerdeps` — Module.registerDependencies — lazy singleton registration

```dart
bridge.registerLazySingleton<${1:Repository}>(
  () => ${1:Repository}Impl(${2:bridge.get<Dependency>()}),
  onDispose: (repo) => repo.dispose(),
);
```

### `mb_module_subscribe` — Module.subscribe — event subscription bound to module lifetime

```dart
subscribe<${1:MyEvent}>(bridge, (event) {
  ${2}
});
```

### `mb_module_warmup` — FeatureModule.warmup — hook after owned deps resolve

```dart
@override
void warmup(ModularBridge bridge) {
  ${1}
}
```

### `mb_modulesready` — onModulesReady — run code after all modules init

```dart
ModularBridge.I.onModulesReady((bridge) async {
  ${1}
});
```

### `mb_new_BridgeAsyncDependencyException` — Instantiate BridgeAsyncDependencyException

```dart
BridgeAsyncDependencyException(${1:type})
```

### `mb_new_BridgeAsyncInterceptorException` — Instantiate BridgeAsyncInterceptorException

```dart
BridgeAsyncInterceptorException(${1:type})
```

### `mb_new_BridgeCircularDependencyException` — Instantiate BridgeCircularDependencyException

```dart
BridgeCircularDependencyException(${1:type}, ${2:resolutionChain})
```

### `mb_new_BridgeConfig` — Instantiate BridgeConfig

```dart
BridgeConfig(environment: ${1:environment})
```

### `mb_new_BridgeConfigKeyNotFoundException` — Instantiate BridgeConfigKeyNotFoundException

```dart
BridgeConfigKeyNotFoundException(${1:key})
```

### `mb_new_BridgeConfigTypeMismatchException` — Instantiate BridgeConfigTypeMismatchException

```dart
BridgeConfigTypeMismatchException(key: ${1:key}, expectedType: ${2:expectedType}, actualType: ${3:actualType})
```

### `mb_new_BridgeDependencyAlreadyRegisteredException` — Instantiate BridgeDependencyAlreadyRegisteredException

```dart
BridgeDependencyAlreadyRegisteredException(${1:type})
```

### `mb_new_BridgeDependencyGraph` — Instantiate BridgeDependencyGraph

```dart
BridgeDependencyGraph(nodes: ${1:nodes}, edges: ${2:edges}, cycles: ${3:cycles})
```

### `mb_new_BridgeDependencyNotFoundException` — Instantiate BridgeDependencyNotFoundException

```dart
BridgeDependencyNotFoundException(${1:type})
```

### `mb_new_BridgeDiagnosticsReport` — Instantiate BridgeDiagnosticsReport

```dart
BridgeDiagnosticsReport(registrations: ${1:registrations}, moduleNames: ${2:moduleNames}, activeScopeNames: ${3:activeScopeNames}, scopeStack: ${4:scopeStack}, activeSubscriptionCount: ${5:activeSubscriptionCount}, pendingAsyncResolutions: ${6:pendingAsyncResolutions}, issues: ${7:issues}, metrics: ${8:metrics})
```

### `mb_new_BridgeErrorReport` — Instantiate BridgeErrorReport

```dart
BridgeErrorReport(exception: ${1:exception})
```

### `mb_new_BridgeEventBus` — Instantiate BridgeEventBus

```dart
BridgeEventBus()
```

### `mb_new_BridgeModuleAlreadyRegisteredException` — Instantiate BridgeModuleAlreadyRegisteredException

```dart
BridgeModuleAlreadyRegisteredException(${1:moduleName})
```

### `mb_new_BridgeModuleInUseException` — Instantiate BridgeModuleInUseException

```dart
BridgeModuleInUseException(moduleName: ${1:moduleName}, dependentModules: ${2:dependentModules})
```

### `mb_new_BridgeModuleMissingDependencyException` — Instantiate BridgeModuleMissingDependencyException

```dart
BridgeModuleMissingDependencyException(moduleName: ${1:moduleName}, missingDependency: ${2:missingDependency})
```

### `mb_new_BridgeModuleNotFoundException` — Instantiate BridgeModuleNotFoundException

```dart
BridgeModuleNotFoundException(${1:moduleName})
```

### `mb_new_BridgeResolutionRequest` — Instantiate BridgeResolutionRequest

```dart
BridgeResolutionRequest(bridge: ${1:bridge}, type: ${2:type}, isAsync: ${3:isAsync})
```

### `mb_new_BridgeResolutionTiming` — Instantiate BridgeResolutionTiming

```dart
BridgeResolutionTiming(request: ${1:request}, elapsed: ${2:elapsed}, succeeded: ${3:succeeded})
```

### `mb_new_BridgeRetryPolicy` — Instantiate BridgeRetryPolicy

```dart
BridgeRetryPolicy()
```

### `mb_new_BridgeScopeNotFoundException` — Instantiate BridgeScopeNotFoundException

```dart
BridgeScopeNotFoundException(${1:scopeName})
```

### `mb_new_BridgeWaitingTimeOutException` — Instantiate BridgeWaitingTimeOutException

```dart
BridgeWaitingTimeOutException(duration: ${1:duration}, pending: ${2:pending}, ready: ${3:ready})
```

### `mb_new_DependencyEdge` — Instantiate DependencyEdge

```dart
DependencyEdge(from: ${1:from}, to: ${2:to})
```

### `mb_new_DependencyInfo` — Instantiate DependencyInfo

```dart
DependencyInfo(key: ${1:key}, lifecycle: ${2:lifecycle}, registrationIndex: ${3:registrationIndex}, isReady: ${4:isReady}, hasInstance: ${5:hasInstance}, hasAsyncResolution: ${6:hasAsyncResolution}, signalsReady: ${7:signalsReady}, dependsOn: ${8:dependsOn})
```

### `mb_new_DependencyMetricEntry` — Instantiate DependencyMetricEntry

```dart
DependencyMetricEntry(resolutions: ${1:resolutions}, cacheHits: ${2:cacheHits}, failures: ${3:failures}, totalMicros: ${4:totalMicros}, maxMicros: ${5:maxMicros})
```

### `mb_new_DependencyMetrics` — Instantiate DependencyMetrics

```dart
DependencyMetrics()
```

### `mb_new_DeveloperLogBridgeErrorReporter` — Instantiate DeveloperLogBridgeErrorReporter

```dart
DeveloperLogBridgeErrorReporter()
```

### `mb_new_Lazy` — Instantiate Lazy

```dart
Lazy(${1:bridge})
```

### `mb_new_ModularBridge` — Instantiate ModularBridge

```dart
ModularBridge()
```

### `mb_nodeId` — Call nodeId(DependencyInfo info)

```dart
BridgeDependencyGraph.nodeId(${1:info})
```

### `mb_on` — Call on

```dart
bridge.on<T>()
```

### `mb_onModulesReady` — Call onModulesReady(FutureOr<void> Function(ModularBridge bridge) callback)

```dart
bridge.onModulesReady(${1:callback})
```

### `mb_override` — 1-line mock override for tests

```dart
bridge.override<${1:Service}>(${2:mockService}${3:, instanceName: 'name'});
```

### `mb_overrideAsync` — Call overrideAsync(Future<T> Function() factory, { String? instanceName, })

```dart
bridge.overrideAsync<T>(${1:factory})
```

### `mb_overrideFactory` — Call overrideFactory(T Function() factory, { String? instanceName, })

```dart
bridge.overrideFactory<T>(${1:factory})
```

### `mb_pause` — Call pause([Future<void>? resumeSignal])

```dart
subscription.pause()
```

### `mb_popScope` — Call popScope

```dart
bridge.popScope()
```

### `mb_popScopesTill` — Call popScopesTill(String name, {bool inclusive = true})

```dart
bridge.popScopesTill(${1:name})
```

### `mb_pushNewScope` — Call pushNewScope({ String? scopeName, void Function(ModularBridge bridge)? init, FutureOr<void> Function...)

```dart
bridge.pushNewScope()
```

### `mb_pushNewScopeAsync` — Call pushNewScopeAsync({ String? scopeName, FutureOr<void> Function(ModularBridge bridge)? init, FutureOr<void...)

```dart
bridge.pushNewScopeAsync()
```

### `mb_quickstart` — Minimal app bootstrap — config + modules + runApp

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bridge = ModularBridge.I;
  bridge.setConfig(await BridgeConfig.fromAsset(
    'assets/config.json',
    loader: rootBundle.loadString,
  ));
  await bridge.registerModules([CoreModule(), AuthModule()]);

  runApp(const MyApp());
}
```

### `mb_record` — Call record(String key, { required int elapsedMicros, required bool cacheHit, required bool failed,...)

```dart
bridge.metrics.record(${1:key}, elapsedMicros: ${2:elapsedMicros}, cacheHit: ${3:cacheHit}, failed: ${4:failed})
```

### `mb_registerAsyncSingleton` — Call registerAsyncSingleton(Future<T> Function() factory, { String? instanceName, bool override = false, void Funct...)

```dart
bridge.registerAsyncSingleton<T>(${1:factory})
```

### `mb_registerCachedFactoryParam` — Call registerCachedFactoryParam(T Function(P1 param1, P2 param2) factory, { String? instanceName, bool override = false...)

```dart
bridge.registerCachedFactoryParam<T, P1, P2>(${1:factory})
```

### `mb_registerCachedFactoryParamAsync` — Call registerCachedFactoryParamAsync(Future<T> Function(P1 param1, P2 param2) factory, { String? instanceName, bool override...)

```dart
bridge.registerCachedFactoryParamAsync<T, P1, P2>(${1:factory})
```

### `mb_registerConfigBinding` — Call registerConfigBinding({ required String configKey, required T Function(dynamic value) decoder, dynamic defaul...)

```dart
bridge.registerConfigBinding<T>(configKey: ${1:configKey}, decoder: ${2:decoder})
```

### `mb_registerFactory` — Call registerFactory(T Function() factory, { String? instanceName, bool override = false, Iterable<Dependenc...)

```dart
bridge.registerFactory<T>(${1:factory})
```

### `mb_registerFactoryAsync` — Call registerFactoryAsync(Future<T> Function() factory, { String? instanceName, bool override = false, Iterable<D...)

```dart
bridge.registerFactoryAsync<T>(${1:factory})
```

### `mb_registerFactoryParam` — Call registerFactoryParam(T Function(P1 param1, P2 param2) factory, { String? instanceName, bool override = false...)

```dart
bridge.registerFactoryParam<T, P1, P2>(${1:factory})
```

### `mb_registerFactoryParamAsync` — Call registerFactoryParamAsync(Future<T> Function(P1 param1, P2 param2) factory, { String? instanceName, bool override...)

```dart
bridge.registerFactoryParamAsync<T, P1, P2>(${1:factory})
```

### `mb_registerLazySingleton` — Call registerLazySingleton(T Function() factory, { String? instanceName, bool override = false, void Function(T in...)

```dart
bridge.registerLazySingleton<T>(${1:factory})
```

### `mb_registerLazySingletonAsync` — Call registerLazySingletonAsync(Future<T> Function() factory, { String? instanceName, bool override = false, void Funct...)

```dart
bridge.registerLazySingletonAsync<T>(${1:factory})
```

### `mb_registerModule` — Call registerModule(FeatureModule module, { bool checkHealth = false, })

```dart
bridge.registerModule(${1:module})
```

### `mb_registerModules` — Call registerModules(List<FeatureModule> modules, { bool checkHealth = false, bool parallel = false, })

```dart
bridge.registerModules(${1:modules})
```

### `mb_registerSingleton` — Call registerSingleton(T instance, { String? instanceName, bool override = false, void Function(T instance)? o...)

```dart
bridge.registerSingleton<T>(${1:instance})
```

### `mb_registerSingletonAsync` — Call registerSingletonAsync(Future<T> Function() factory, { String? instanceName, bool override = false, void Funct...)

```dart
bridge.registerSingletonAsync<T>(${1:factory})
```

### `mb_registerSingletonWithDependencies` — Call registerSingletonWithDependencies({ required T Function(ModularBridge bridge) factoryFunc, required Iterable<DependencyKe...)

```dart
bridge.registerSingletonWithDependencies<T>(factoryFunc: ${1:factoryFunc}, dependsOn: ${2:dependsOn})
```

### `mb_registerSingletonWithDependenciesAsync` — Call registerSingletonWithDependenciesAsync({ required FutureOr<T> Function(ModularBridge bridge) factoryFunc, required Iterable<De...)

```dart
bridge.registerSingletonWithDependenciesAsync<T>(factoryFunc: ${1:factoryFunc}, dependsOn: ${2:dependsOn})
```

### `mb_register_async` — registerAsyncSingleton — async factory with retry policy

```dart
bridge.registerAsyncSingleton<${1:ApiClient}>(
  () => ${1:ApiClient}.connect(${2:config.getString('apiBaseUrl')}),
  eager: ${3|true,false|},
  retryPolicy: const BridgeRetryPolicy(
    maxAttempts: ${4:3},
    delay: Duration(milliseconds: ${5:200}),
    backoff: ${6:2.0},
  ),
);
```

### `mb_register_factory` — registerFactory — new instance per resolution

```dart
bridge.registerFactory<${1:Service}>(() => ${1:Service}());
```

### `mb_register_lazy` — registerLazySingleton — created on first get<T>()

```dart
bridge.registerLazySingleton<${1:Repository}>(
  () => ${1:Repository}Impl(${2:bridge.get<Dependency>()}),
  dependsOn: [dep<${3:Dependency}>()],
);
```

### `mb_register_module` — Register a single FeatureModule

```dart
await ModularBridge.I.registerModule(${1:AuthModule()}${2:, checkHealth: true});
```

### `mb_register_modules` — Register a batch of modules (topologically sorted)

```dart
await ModularBridge.I.registerModules([
  ${1:CoreModule()},
  ${2:AuthModule()},
  ${3:HomeModule()},
]);
```

### `mb_register_param` — registerFactoryParam + getParam pair

```dart
bridge.registerFactoryParam<${1:Handler}, ${2:String}, ${3:int}>(
  (${2:param1}, ${3:param2}) => ${1:Handler}(${2:param1}, ${3:param2}),
);

final handler = bridge.getParam<${1:Handler}, ${2:String}, ${3:int}>(
  param1: '${4}',
  param2: ${5:0},
);
```

### `mb_register_singleton` — registerSingleton — eager shared instance

```dart
bridge.registerSingleton<${1:Service}>(${1:Service}()${2:, onDispose: (s) => s.dispose()});
```

### `mb_register_withdeps` — registerSingletonWithDependencies — ordered startup

```dart
bridge.registerSingletonWithDependencies<${1:CheckoutService}>(
  factoryFunc: (bridge) => ${1:CheckoutService}(
    bridge.get<${2:PaymentGateway}>(),
  ),
  dependsOn: [dep<${2:PaymentGateway}>()],
);
```

### `mb_remove` — Call remove(String key)

```dart
config.remove(${1:key})
```

### `mb_removeConfigValue` — Call removeConfigValue(String key)

```dart
scope.removeConfigValue(${1:key})
```

### `mb_removeEventInterceptor` — Call removeEventInterceptor(BridgeEventInterceptor interceptor)

```dart
bridge.eventBus.removeEventInterceptor(${1:interceptor})
```

### `mb_removeModuleDependencies` — Call removeModuleDependencies(String moduleName)

```dart
scope.removeModuleDependencies(${1:moduleName})
```

### `mb_removeResolutionInterceptor` — Call removeResolutionInterceptor(BridgeResolutionInterceptor interceptor)

```dart
bridge.removeResolutionInterceptor(${1:interceptor})
```

### `mb_removeRuntimeOverrides` — Call removeRuntimeOverrides

```dart
config.removeRuntimeOverrides()
```

### `mb_report` — Call report(Object? error)

```dart
bridge.report(${1:error})
```

### `mb_reset` — Reset the container (tests / logout flows)

```dart
await bridge.reset(disposeInstances: ${1|true,false|});
```

### `mb_resetInstance` — Call resetInstance

```dart
ModularBridge.resetInstance()
```

### `mb_resetLazySingleton` — Call resetLazySingleton({ String? instanceName, bool disposeHooks = true, FutureOr<void> Function(T instance)? ...)

```dart
bridge.resetLazySingleton<T>()
```

### `mb_resetLazySingletons` — Call resetLazySingletons({bool disposeHooks = true})

```dart
bridge.resetLazySingletons()
```

### `mb_resetMetrics` — Call resetMetrics

```dart
bridge.resetMetrics()
```

### `mb_resetScope` — Call resetScope({bool disposeInstances = true})

```dart
bridge.resetScope()
```

### `mb_resolveTarget` — Call resolveTarget(DependencyInfo from, DependencyKey dep)

```dart
bridge.resolveTarget(${1:from}, ${2:dep})
```

### `mb_resume` — Call resume

```dart
subscription.resume()
```

### `mb_retry` — BridgeRetryPolicy for flaky async dependencies

```dart
const retryPolicy = BridgeRetryPolicy(
  maxAttempts: ${1:3},
  delay: Duration(milliseconds: ${2:250}),
  backoff: ${3:2.0},
  retryIf: (error) => error is! BridgeConfigKeyNotFoundException,
);
```

### `mb_scope` — Request/session-scoped dependencies

```dart
final scope = await bridge.createScopeAsync((scope) async {
  scope.registerLazySingleton<${1:RequestContext}>(
    () => RequestContext(${2:requestId}),
  );
});

try {
  final ctx = scope.get<${1:RequestContext}>();
  ${3}
} finally {
  await scope.dispose();
}
```

### `mb_scope_push` — pushNewScope — stack-based scoping

```dart
bridge.pushNewScope(
  scopeName: '${1:request}',
  init: (bridge) {
    ${2}
  },
  isFinal: ${3|true,false|},
);
```

### `mb_scope_pushasync` — pushNewScopeAsync — async init + scoped config override

```dart
await bridge.pushNewScopeAsync(
  scopeName: '${1:request}',
  init: (bridge) async {
    bridge.registerSingleton<${2:RequestContext}>(
      ${2:RequestContext}(${3:requestId}),
    );
    bridge.currentScope!.setConfigValue('tenant', '${4:acme}');
    ${5}
  },
  dispose: () async {
    ${6}
  },
);
```

### `mb_seal` — Call seal

```dart
scope.seal()
```

### `mb_set` — Call set(String key, dynamic value)

```dart
config.set(${1:key}, ${2:value})
```

### `mb_setAll` — Call setAll(Map<String, dynamic> values)

```dart
config.setAll(${1:values})
```

### `mb_setConfig` — Call setConfig(BridgeConfig newConfig)

```dart
bridge.setConfig(${1:newConfig})
```

### `mb_setConfigValue` — Call setConfigValue(String key, dynamic value)

```dart
scope.setConfigValue(${1:key}, ${2:value})
```

### `mb_setMockInstance` — Call setMockInstance(ModularBridge bridge)

```dart
ModularBridge.setMockInstance(${1:bridge})
```

### `mb_signalReady` — Call signalReady([Object? instance])

```dart
bridge.signalReady()
```

### `mb_singleton` — singleton — short alias for registerSingleton

```dart
bridge.singleton<${1:Service}>(${1:Service}());
```

### `mb_snapshot` — Call snapshot

```dart
bridge.metrics.snapshot()
```

### `mb_switchEnvironment` — Call switchEnvironment(BridgeEnvironment newEnvironment, { Map<String, dynamic>? runtimeOverrides, })

```dart
config.switchEnvironment(${1:newEnvironment})
```

### `mb_test` — Isolated bridge for unit/widget tests

```dart
final bridge = ModularBridge.createIsolated(
  config: BridgeConfig(environment: BridgeEnvironment.dev),
);
addTearDown(bridge.dispose);

bridge.registerSingleton<${1:Service}>(${1:Service}());
final service = bridge.get<${1:Service}>();
```

### `mb_timing` — Call timing(void Function(BridgeResolutionTiming timing) onTiming,)

```dart
BridgeInterceptors.timing(${1:onTiming})
```

### `mb_toDot` — Call toDot

```dart
bridge.dependencyGraph().toDot()
```

### `mb_transient` — Call transient(T Function() factory, { String? instanceName, bool override = false, Iterable<Dependenc...)

```dart
bridge.transient<T>(${1:factory})
```

### `mb_tryGetAsync` — Call tryGetAsync({String? instanceName})

```dart
bridge.tryGetAsync<T>()
```

### `mb_tryGetModule` — Call tryGetModule

```dart
bridge.tryGetModule<M>()
```

### `mb_tryget` — Optional resolution — null when not registered

```dart
final ${1:Service}? ${2:service} = bridge.tryGet<${1:Service}>();
```

### `mb_unregister` — Call unregister({ String? instanceName, bool throwOnMissing = false, })

```dart
bridge.unregister<T>()
```

### `mb_unregisterModule` — Call unregisterModule({bool force = false})

```dart
bridge.unregisterModule<M>()
```

### `mb_unregisterModuleByName` — Call unregisterModuleByName(String moduleName, {bool force = false})

```dart
bridge.unregisterModuleByName(${1:moduleName})
```

### `mb_unregistered` — Unregister a module / dependency

```dart
await bridge.unregisterModule<${1:FeatureModule}>${2|, force: true|}();
```

### `mb_unstackScope` — Call unstackScope(BridgeScope scope)

```dart
bridge.unstackScope(${1:scope})
```

### `mb_warmup` — Eagerly resolve all singleton-style registrations

```dart
await bridge.warmup();
```


## Class constructors (`mb.new.*`)


## Property getters (`mb.get.*`)


## Top-level functions (`mb.fn.*`)


---

_Generated by `generate_snippets.dart` — do not edit by hand._
