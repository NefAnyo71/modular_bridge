/// High-performance, zero-dependency modular dependency injection,
/// type-safe configuration, and decoupled event-bus architecture framework.
///
/// Pure Dart core: no Flutter SDK dependency. Flutter widgets and helpers
/// (`ModularBridgeScope`, `ModularBridgeProvider`, context extensions,
/// `ModularBridgeInspector`, asset/env loaders) live in the companion
/// package `package:modular_bridge_flutter`.
library;

// Core DI & Container
export 'src/core/container/dependency_descriptor.dart'
    show DependencyKey, DependencyLifecycle, Disposable, dep;
export 'src/core/lazy.dart' show Lazy;
export 'src/core/container/modular_bridge_container.dart'
    show ModularBridge, BridgeDiagnosticsReport;
export 'src/core/container/bridge_scope.dart'
    show BridgeScope, WillSignalReady, DependencyInfo;
export 'src/core/container/dependency_event.dart'
    show
        DependencyChangeKind,
        DependencyRegistrationEvent,
        ShadowChangeHandlers;
export 'src/core/container/dependency_graph.dart'
    show BridgeDependencyGraph, DependencyEdge;
export 'src/core/container/dependency_metrics.dart'
    show DependencyMetrics, DependencyMetricEntry;
export 'src/core/container/bridge_retry_policy.dart' show BridgeRetryPolicy;
export 'src/core/container/resolution_interceptor.dart'
    show
        BridgeInterceptors,
        BridgeResolutionInterceptor,
        BridgeResolutionNext,
        BridgeResolutionRequest,
        BridgeResolutionTiming;

// Exceptions, error reporting & annotations
export 'src/core/annotations.dart'
    show immutable, mustCallSuper, protected, visibleForTesting;
export 'src/core/errors/bridge_error_reporter.dart'
    show
        BridgeErrorReport,
        BridgeErrorReporter,
        DeveloperLogBridgeErrorReporter,
        bridgeErrorReporter,
        reportBridgeError;
export 'src/core/exceptions/bridge_exceptions.dart';

// Module
export 'src/module/feature_module.dart' show FeatureModule, ModuleHealthResult;

// Config & Environments
export 'src/config/bridge_config.dart' show BridgeConfig;
export 'src/config/bridge_environment.dart' show BridgeEnvironment;
export 'src/config/env_file.dart' show parseEnvFile;

// Event Bus
export 'src/event_bus/bridge_event.dart' show BridgeEvent;
export 'src/event_bus/bridge_event_bus.dart'
    show BridgeEventBus, BridgeEventInterceptor;
export 'src/event_bus/bridge_subscription.dart' show BridgeSubscription;
