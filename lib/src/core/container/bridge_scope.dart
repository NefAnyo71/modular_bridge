import '../exceptions/bridge_exceptions.dart';
import 'dependency_descriptor.dart';
import 'modular_bridge_container.dart';

/// A named dependency scope for request/session-scoped registrations.
///
/// Dependencies registered on a scope are resolved **only** through the scope
/// itself (`scope.get<T>()`); they are invisible to [ModularBridge.get] and to
/// other scopes. This makes scopes ideal for per-request or per-session state
/// (e.g. an authenticated user's cart or a single HTTP request context).
///
/// Resolution falls back to the parent [ModularBridge] when a type is not
/// registered on the scope, so scoped factories can freely consume global
/// singletons via `scope.get<T>()`.
///
/// Note: scopes currently support synchronous lifecycles only —
/// `registerAsyncSingleton`/`getAsync` are not available on a [BridgeScope];
/// resolve async dependencies through the parent [ModularBridge] instead.
///
/// Call [dispose] when the scope ends (e.g. end of a request); every
/// dependency owned by the scope is disposed and its `onDispose` hooks run.
///
/// ```dart
/// final scope = bridge.createScope();
/// scope.registerSingleton<RequestContext>(RequestContext(userId: 'u1'));
/// // ... handle request ...
/// await scope.dispose();
/// ```
final class BridgeScope {
  /// Creates a scope bound to [bridge].
  ///
  /// Prefer [ModularBridge.createScope] for discoverability.
  BridgeScope(this.bridge);

  /// The parent container this scope delegates unregistered lookups to.
  final ModularBridge bridge;

  final Map<DependencyKey, DependencyDescriptor<dynamic>> _registry = {};
  final List<DependencyKey> _resolutionStack = [];
  bool _isDisposed = false;

  /// Whether [dispose] has been called on this scope.
  bool get isDisposed => _isDisposed;

  void _ensureActive() {
    if (_isDisposed) {
      throw StateError('Cannot use a disposed BridgeScope.');
    }
  }

  // ---------------------------------------------------------------------------
  // REGISTRATION
  // ---------------------------------------------------------------------------

  /// Registers an existing [instance] as an eager singleton within this scope.
  void registerSingleton<T extends Object>(
    T instance, {
    String? instanceName,
    bool override = false,
    void Function(T instance)? onDispose,
  }) {
    _ensureActive();
    final key = DependencyKey(T, instanceName);
    if (_registry.containsKey(key) && !override) {
      throw BridgeDependencyAlreadyRegisteredException(T,
          instanceName: instanceName);
    }
    if (override && _registry.containsKey(key)) {
      _registry[key]?.dispose();
    }
    _registry[key] = DependencyDescriptor<T>(
      key: key,
      lifecycle: DependencyLifecycle.singleton,
      factory: () => instance,
      instance: instance,
      onDispose: onDispose,
    );
  }

  /// Registers a lazy singleton within this scope, instantiated on first resolution.
  void registerLazySingleton<T extends Object>(
    T Function() factory, {
    String? instanceName,
    bool override = false,
    void Function(T instance)? onDispose,
  }) {
    _ensureActive();
    final key = DependencyKey(T, instanceName);
    if (_registry.containsKey(key) && !override) {
      throw BridgeDependencyAlreadyRegisteredException(T,
          instanceName: instanceName);
    }
    if (override && _registry.containsKey(key)) {
      _registry[key]?.dispose();
    }
    _registry[key] = DependencyDescriptor<T>(
      key: key,
      lifecycle: DependencyLifecycle.lazySingleton,
      factory: factory,
      onDispose: onDispose,
    );
  }

  /// Registers a transient factory within this scope.
  void registerFactory<T extends Object>(
    T Function() factory, {
    String? instanceName,
    bool override = false,
  }) {
    _ensureActive();
    final key = DependencyKey(T, instanceName);
    if (_registry.containsKey(key) && !override) {
      throw BridgeDependencyAlreadyRegisteredException(T,
          instanceName: instanceName);
    }
    if (override && _registry.containsKey(key)) {
      _registry[key]?.dispose();
    }
    _registry[key] = DependencyDescriptor<T>(
      key: key,
      lifecycle: DependencyLifecycle.factory,
      factory: factory,
    );
  }

  // ---------------------------------------------------------------------------
  // RESOLUTION
  // ---------------------------------------------------------------------------

  /// Resolves an instance of type [T] from this scope, falling back to the
  /// parent [ModularBridge] when [T] is not registered on the scope.
  T get<T extends Object>({String? instanceName}) {
    _ensureActive();
    final key = DependencyKey(T, instanceName);
    final descriptor = _registry[key];

    if (descriptor == null) {
      return bridge.get<T>(instanceName: instanceName);
    }

    if (descriptor.lifecycle == DependencyLifecycle.asyncSingleton) {
      throw BridgeAsyncDependencyException(T);
    }

    if (_resolutionStack.contains(key)) {
      throw BridgeCircularDependencyException(
        T,
        _resolutionStack.map((k) => k.type).toList(),
      );
    }

    _resolutionStack.add(key);
    try {
      return descriptor.resolve() as T;
    } finally {
      _resolutionStack.removeLast();
    }
  }

  /// Callable syntax shortcut for [get].
  T call<T extends Object>({String? instanceName}) =>
      get<T>(instanceName: instanceName);

  /// Attempts to resolve [T] from this scope or the parent bridge.
  T? tryGet<T extends Object>({String? instanceName}) {
    if (isRegistered<T>(instanceName: instanceName)) {
      return get<T>(instanceName: instanceName);
    }
    return bridge.tryGet<T>(instanceName: instanceName);
  }

  /// Checks whether [T] is registered on this scope or the parent bridge.
  bool isRegistered<T extends Object>({String? instanceName}) {
    final key = DependencyKey(T, instanceName);
    return _registry.containsKey(key) ||
        bridge.isRegistered<T>(instanceName: instanceName);
  }

  /// Unregisters and disposes the scope-local dependency of type [T].
  ///
  /// Only affects registrations made directly on this scope; parent bridge
  /// registrations are untouched.
  void unregister<T extends Object>({String? instanceName}) {
    _ensureActive();
    final key = DependencyKey(T, instanceName);
    _registry.remove(key)?.dispose();
  }

  // ---------------------------------------------------------------------------
  // DISPOSAL
  // ---------------------------------------------------------------------------

  /// Disposes every dependency owned by this scope and marks it inactive.
  ///
  /// Idempotent: calling [dispose] more than once is a no-op.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _resolutionStack.clear();

    final descriptors = _registry.values.toList().reversed;
    for (final descriptor in descriptors) {
      descriptor.dispose();
    }
    _registry.clear();
  }
}
