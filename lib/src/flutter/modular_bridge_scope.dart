import 'dart:async';
import 'package:flutter/widgets.dart';
import '../config/bridge_config.dart';
import '../config/bridge_environment.dart';
import '../core/container/modular_bridge_container.dart';

/// Provides a [ModularBridge] container down the widget tree.
class ModularBridgeScope extends InheritedWidget {
  /// Creates a [ModularBridgeScope].
  const ModularBridgeScope({
    super.key,
    required this.bridge,
    this.environment,
    required super.child,
  });

  /// The [ModularBridge] container instance made available to descendants.
  final ModularBridge bridge;

  /// Optional current environment to trigger rebuilds when flavors switch.
  final BridgeEnvironment? environment;

  /// Retrieves the nearest [ModularBridge] from the widget tree.
  ///
  /// Falls back to [ModularBridge.instance] if no [ModularBridgeScope] is found.
  static ModularBridge of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ModularBridgeScope>();
    return scope?.bridge ?? ModularBridge.instance;
  }

  /// Retrieves the nearest [ModularBridge] if present, otherwise returns null.
  static ModularBridge? maybeOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ModularBridgeScope>();
    return scope?.bridge;
  }

  @override
  bool updateShouldNotify(ModularBridgeScope oldWidget) {
    return bridge != oldWidget.bridge || environment != oldWidget.environment;
  }
}

/// A reactive provider widget that rebuilds its subtree whenever [ModularBridge.config]
/// environment changes (e.g. during a runtime hot-switch).
class ModularBridgeProvider extends StatefulWidget {
  /// Creates a [ModularBridgeProvider].
  const ModularBridgeProvider({
    super.key,
    this.bridge,
    required this.child,
  });

  /// The bridge instance to provide. Defaults to [ModularBridge.instance].
  final ModularBridge? bridge;

  /// The child widget subtree.
  final Widget child;

  @override
  State<ModularBridgeProvider> createState() => _ModularBridgeProviderState();
}

class _ModularBridgeProviderState extends State<ModularBridgeProvider> {
  late ModularBridge _bridge;
  StreamSubscription<BridgeEnvironment>? _envSubscription;
  StreamSubscription<BridgeConfig>? _configSubscription;

  @override
  void initState() {
    super.initState();
    _bridge = widget.bridge ?? ModularBridge.instance;
    _subscribe();
  }

  @override
  void didUpdateWidget(ModularBridgeProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newBridge = widget.bridge ?? ModularBridge.instance;
    if (_bridge != newBridge) {
      _detachSubscriptions();
      _bridge = newBridge;
      _subscribe();
    }
  }

  void _subscribe() {
    // Migrate to a swapped BridgeConfig: the old config's streams go stale.
    _configSubscription = _bridge.onConfigChanged.listen((_) {
      unawaited(_envSubscription?.cancel());
      _envSubscription = null;
      _subscribeToEnvironment(_bridge.config);
      if (mounted) {
        setState(() {});
      }
    });
    _subscribeToEnvironment(_bridge.config);
  }

  void _subscribeToEnvironment(BridgeConfig config) {
    _envSubscription = config.onEnvironmentChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _detachSubscriptions() {
    unawaited(_envSubscription?.cancel());
    unawaited(_configSubscription?.cancel());
    _envSubscription = null;
    _configSubscription = null;
  }

  @override
  void dispose() {
    _detachSubscriptions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ModularBridgeScope(
      bridge: _bridge,
      environment: _bridge.config.environment,
      child: widget.child,
    );
  }
}
