import 'container/bridge_scope.dart';
import 'container/modular_bridge_container.dart';

/// A deferred dependency handle that breaks circular dependencies.
///
/// Register a `Lazy<T>` (or inject `bridge.lazy<T>()`) where resolving a
/// dependency eagerly would create a registration cycle: the wrapped
/// dependency is only looked up when [value] is accessed — by which time
/// both registrations normally exist.
///
/// ```dart
/// bridge.registerLazySingleton<ServiceA>(
///   () => ServiceA(bridge.lazy<ServiceB>()),
/// );
/// bridge.registerLazySingleton<ServiceB>(
///   () => ServiceB(bridge.get<ServiceA>()),
/// );
///
/// final a = bridge.get<ServiceA>();
/// final b = a.lazyB.value; // resolved on demand, no cycle
/// ```
///
/// Resolution goes through the owning bridge/scope's normal lookup rules —
/// including the active scope chain for [Lazy] created via
/// [ModularBridge.lazy] or [BridgeScope.lazy] — so named instances and
/// scope-local shadowing behave exactly like a direct `get` call.
final class Lazy<T extends Object> {
  Lazy._(
    this.instanceName,
    T Function() get,
    Future<T> Function() getAsync,
  )   : _get = get,
        _getAsync = getAsync;

  /// Creates a [Lazy] resolving [T] through [bridge]'s scope-aware lookup.
  factory Lazy(ModularBridge bridge, {String? instanceName}) {
    return Lazy<T>._(
      instanceName,
      () => bridge.get<T>(instanceName: instanceName),
      () => bridge.getAsync<T>(instanceName: instanceName),
    );
  }

  /// Creates a [Lazy] bound to [scope]'s resolution hierarchy (scope →
  /// parent scopes → root bridge).
  factory Lazy.scoped(BridgeScope scope, {String? instanceName}) {
    return Lazy<T>._(
      instanceName,
      () => scope.get<T>(instanceName: instanceName),
      () => scope.getAsync<T>(instanceName: instanceName),
    );
  }

  final T Function() _get;
  final Future<T> Function() _getAsync;

  /// The optional named-instance qualifier this [Lazy] resolves.
  final String? instanceName;

  /// Resolves [T] through the normal lookup path (cached for singletons).
  ///
  /// Throws [BridgeAsyncDependencyException] when [T] uses an async
  /// lifecycle — use [resolveAsync] instead.
  T get value => _get();

  /// Asynchronously resolves [T]; required for async lifecycles and usable
  /// for every other lifecycle as well.
  Future<T> resolveAsync() => _getAsync();
}
