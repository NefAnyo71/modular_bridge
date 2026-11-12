import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/container/modular_bridge_container.dart';
import '../event_bus/bridge_event.dart';
import '../event_bus/bridge_subscription.dart';

/// Base abstract class for defining isolated feature modules.
///
/// Each module encapsulates its own dependencies (repositories, use cases, services),
/// declares prerequisites, and communicates with other modules solely via
/// the [BridgeEventBus] or registered public interfaces.
///
/// Example:
/// ```dart
/// final class AuthModule extends FeatureModule {
///   @override
///   void registerDependencies(ModularBridge bridge) {
///     bridge.registerLazySingleton<AuthRepository>(() => AuthRepositoryImpl());
///   }
///
///   @override
///   void init(ModularBridge bridge) {
///     subscribe<UserSessionExpiredEvent>(bridge, (event) {
///       // handle session expiration cleanly
///     });
///   }
/// }
/// ```
abstract class FeatureModule {
  /// Default constructor for subclasses.
  FeatureModule();

  /// Unique name for this module. Defaults to the concrete class name.
  String get name => runtimeType.toString();

  /// Other [FeatureModule] types that must be registered before this module can initialize.
  List<Type> get dependencies => const [];

  final List<BridgeSubscription> _internalSubscriptions = [];

  /// Subscribes to events on the [ModularBridge.eventBus] bound to this module's lifetime.
  ///
  /// Any subscription created via this method is automatically canceled when
  /// [dispose] is called.
  BridgeSubscription subscribe<T extends BridgeEvent>(
    ModularBridge bridge,
    void Function(T event) onData,
  ) {
    final sub = bridge.eventBus.subscribe<T>(
      onData,
      ownerId: name,
    );
    _internalSubscriptions.add(sub);
    return sub;
  }

  /// Registers module-specific dependencies into the [bridge] container.
  void registerDependencies(ModularBridge bridge);

  /// Lifecycle hook invoked after dependencies have been registered and verified.
  FutureOr<void> init(ModularBridge bridge) {}

  /// Lifecycle hook invoked when the module is being unregistered or the bridge is reset.
  ///
  /// Automatically cancels all subscriptions created via [subscribe].
  @mustCallSuper
  FutureOr<void> dispose(ModularBridge bridge) async {
    for (final sub in _internalSubscriptions) {
      await sub.cancel();
    }
    _internalSubscriptions.clear();
  }
}
