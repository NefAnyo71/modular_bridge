import 'package:flutter/foundation.dart';

/// Defines the lifetime and instantiation strategy of a registered dependency.
enum DependencyLifecycle {
  /// Instantiated immediately and cached as a single instance for the lifetime of the container.
  singleton,

  /// Instantiated on first access via a factory function and subsequently cached.
  lazySingleton,

  /// A brand new instance is created every time the dependency is requested.
  factory,

  /// Instantiated asynchronously on first access via an async factory function
  /// and cached. Must be resolved with `getAsync<T>()`, not `get<T>()`.
  asyncSingleton,
}

/// Identifies a registered dependency by its Dart [type] and optional [name].
@immutable
final class DependencyKey {
  /// Creates a [DependencyKey].
  const DependencyKey(this.type, [this.name]);

  /// The static or runtime Dart type of the dependency.
  final Type type;

  /// An optional qualifier to allow multiple registrations of the same type.
  final String? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DependencyKey &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          name == other.name;

  @override
  int get hashCode => Object.hash(type, name);

  @override
  String toString() => name != null ? '$type(\'$name\')' : '$type';
}

/// Internal metadata descriptor managing instance creation, caching, and disposal.
final class DependencyDescriptor<T> {
  /// Creates a [DependencyDescriptor].
  DependencyDescriptor({
    required this.key,
    required this.lifecycle,
    T Function()? factory,
    this.asyncFactory,
    T? instance,
    this.ownerModuleName,
    this.onDispose,
  })  : factory = factory ??
            (() => throw StateError(
                'Dependency ${key.toString()} has no synchronous factory.')),
        _cachedInstance = instance;

  /// The unique lookup key.
  final DependencyKey key;

  /// The lifecycle strategy for this dependency.
  final DependencyLifecycle lifecycle;

  /// Factory function that produces an instance of [T].
  final T Function() factory;

  /// Async factory function for [DependencyLifecycle.asyncSingleton] dependencies.
  final Future<T> Function()? asyncFactory;

  /// The optional module name that owns this dependency registration.
  final String? ownerModuleName;

  /// Optional hook executed when this dependency is unregistered or container reset.
  final void Function(T instance)? onDispose;

  T? _cachedInstance;
  Future<T>? _asyncFuture;
  bool _disposed = false;

  /// Indicates whether a lazy singleton has already been resolved and cached.
  bool get hasInstance => _cachedInstance != null;

  /// Indicates whether an [DependencyLifecycle.asyncSingleton] resolution is
  /// in-flight or already completed. Concurrent [resolveAsync] calls share
  /// the same underlying future.
  bool get hasAsyncResolution => _asyncFuture != null;

  /// Resolves the instance according to its [lifecycle].
  ///
  /// Throws a [StateError] for [DependencyLifecycle.asyncSingleton];
  /// use [resolveAsync] instead.
  T resolve() {
    if (lifecycle == DependencyLifecycle.asyncSingleton) {
      throw StateError(
        'Dependency ${key.toString()} is asynchronous and must be resolved '
        'with resolveAsync() / getAsync<T>().',
      );
    }
    switch (lifecycle) {
      case DependencyLifecycle.singleton:
      case DependencyLifecycle.lazySingleton:
        return _cachedInstance ??= factory();
      case DependencyLifecycle.factory:
        return factory();
      case DependencyLifecycle.asyncSingleton:
        // Unreachable: guarded above.
        throw StateError('unreachable');
    }
  }

  /// Resolves the instance asynchronously.
  ///
  /// For synchronous lifecycles this simply wraps [resolve] in a future.
  /// For [DependencyLifecycle.asyncSingleton] the factory future is cached so
  /// concurrent and repeated calls share a single resolution.
  Future<T> resolveAsync() {
    switch (lifecycle) {
      case DependencyLifecycle.asyncSingleton:
        return _asyncFuture ??= _resolveAsyncFactory();
      case DependencyLifecycle.singleton:
      case DependencyLifecycle.lazySingleton:
      case DependencyLifecycle.factory:
        return Future<T>.value(resolve());
    }
  }

  /// Invokes the async factory and caches the resolved instance.
  ///
  /// On failure the cached future is cleared so the next [resolveAsync]
  /// call retries the factory instead of replaying the same error.
  Future<T> _resolveAsyncFactory() async {
    try {
      final instance = await asyncFactory!();
      if (!_disposed) {
        _cachedInstance = instance;
      }
      return instance;
    } catch (_) {
      _asyncFuture = null;
      rethrow;
    }
  }

  /// Disposes the cached instance, executing [onDispose] if provided.
  ///
  /// If an [DependencyLifecycle.asyncSingleton] is still resolving, disposal
  /// is deferred until the in-flight future completes.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    final pending = _asyncFuture;
    if (pending != null && _cachedInstance == null) {
      // Instance still being created: run onDispose once it resolves.
      // Resolution errors are already surfaced to the awaiting callers.
      pending.then((instance) => _runOnDispose(instance)).catchError((_) {});
    } else {
      _runOnDispose(_cachedInstance);
    }
    _cachedInstance = null;
    _asyncFuture = null;
  }

  void _runOnDispose(T? instance) {
    if (instance == null) return;
    try {
      onDispose?.call(instance);
    } catch (e, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: stackTrace,
          library: 'modular_bridge',
          context:
              ErrorDescription('While disposing dependency ${key.toString()}'),
        ),
      );
    }
  }
}
