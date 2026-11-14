import 'package:flutter/widgets.dart';
import 'package:modular_bridge/modular_bridge.dart';

import 'modular_bridge_scope.dart';

/// Ergonomic Flutter [BuildContext] extensions for interacting with [ModularBridge].
extension ModularBridgeContextX on BuildContext {
  /// The active [ModularBridge] resolved from [ModularBridgeScope] or [ModularBridge.instance].
  ModularBridge get bridge => ModularBridgeScope.of(this);

  /// Resolves a dependency of type [T] from the container.
  T get<T extends Object>({String? instanceName}) =>
      bridge.get<T>(instanceName: instanceName);

  /// Attempts to resolve a dependency of type [T], returning null if not registered.
  T? tryGet<T extends Object>({String? instanceName}) =>
      bridge.tryGet<T>(instanceName: instanceName);

  /// The active [BridgeConfig].
  BridgeConfig get config => bridge.config;

  /// Publishes a [BridgeEvent] through the container's event bus.
  void publish<T extends BridgeEvent>(T event) => bridge.publish(event);
}
