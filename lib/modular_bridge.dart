/// High-performance, zero-dependency modular dependency injection,
/// type-safe configuration, and decoupled event-bus architecture framework for Flutter.
library;

// Core DI & Container
export 'src/core/container/dependency_descriptor.dart'
    show DependencyKey, DependencyLifecycle;
export 'src/core/container/modular_bridge_container.dart' show ModularBridge;

// Exceptions
export 'src/core/exceptions/bridge_exceptions.dart';

// Module
export 'src/module/feature_module.dart' show FeatureModule;

// Config & Environments
export 'src/config/bridge_config.dart' show BridgeConfig;
export 'src/config/bridge_environment.dart' show BridgeEnvironment;

// Event Bus
export 'src/event_bus/bridge_event.dart' show BridgeEvent;
export 'src/event_bus/bridge_event_bus.dart' show BridgeEventBus;
export 'src/event_bus/bridge_subscription.dart' show BridgeSubscription;

// Flutter Widgets & Extensions
export 'src/flutter/modular_bridge_extensions.dart';
export 'src/flutter/modular_bridge_scope.dart'
    show ModularBridgeProvider, ModularBridgeScope;
