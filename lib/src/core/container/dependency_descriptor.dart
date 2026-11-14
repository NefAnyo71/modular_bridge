import 'dart:async';

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

  /// Instantiated asynchronously on every call via an async factory function.
  /// Must be resolved with `getAsync<T>()`, not `get<T>()`.
  asyncFactory,
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

/// Interface for dependencies that manage their own disposal.
///
/// When a registered instance implements [Disposable] and no explicit
/// `onDispose`/`disposingFunction` hook was provided, the container calls
/// [onDispose] automatically during unregister, scope pop, or reset —
/// mirroring `get_it`'s `Disposable` support.
abstract class Disposable {
  /// Releases resources held by this instance.
  FutureOr<void> onDispose();
}

/// Internal metadata descriptor managing instance creation, caching, and disposal.
final class DependencyDescriptor<T> {
  /// Creates a [DependencyDescriptor].
  DependencyDescriptor({
    required this.key,
    required this.lifecycle,
    this.registrationIndex = 0,
    T Function()? factory,
    this.asyncFactory,
    T? instance,
    this.ownerModuleName,
    this.onDispose,
    this.eagerAsync = false,
    this.signalsReady = false,
    this.dependsOn = const [],
    this.onCreated,
    this.scopeName,
    this.paramFactory,
    this.paramAsyncFactory,
    this.paramCached = false,
  })  : factory = factory ??
            (() => throw StateError(
                'Dependency ${key.toString()} has no synchronous factory.')),
        _cachedInstance = instance {
    if (lifecycle == DependencyLifecycle.singleton && !signalsReady) {
      _readyCompleter.complete();
    }
  }

  /// The unique lookup key.
  final DependencyKey key;

  /// The lifecycle strategy for this dependency.
  final DependencyLifecycle lifecycle;

  /// Monotonic registration order used for deterministic LIFO disposal.
  final int registrationIndex;

  /// Factory function that produces an instance of [T].
  final T Function() factory;

  /// Async factory function for async lifecycles.
  final Future<T> Function()? asyncFactory;

  /// The optional module name that owns this dependency registration.
  final String? ownerModuleName;

  /// Optional hook executed when this dependency is unregistered or container reset.
  final FutureOr<void> Function(T instance)? onDispose;

  /// Whether an [DependencyLifecycle.asyncSingleton] resolution was started
  /// eagerly at registration time. Only eager async singletons participate
  /// in [ModularBridge.allReady].
  final bool eagerAsync;

  /// Whether readiness must be signalled manually through
  /// `signalReady(instance)` instead of completing automatically.
  final bool signalsReady;

  /// Dependencies that must be resolved before this registration's factory
  /// is invoked.
  final List<DependencyKey> dependsOn;

  /// Optional callback invoked after a new instance has been created.
  final void Function(T instance)? onCreated;

  /// Name of the [BridgeScope] that owns this registration, if any.
  final String? scopeName;

  /// Optional in-flight orchestration future for
  /// `registerSingletonWithDependencies`. While non-null the registration is
  /// not considered ready.
  Future<void>? pendingResult;

  /// Type-erased parameterized sync factory used by `getParam`.
  final T Function(Object? param1, Object? param2)? paramFactory;

  /// Type-erased parameterized async factory used by `getParamAsync`.
  final Future<T> Function(Object? param1, Object? param2)? paramAsyncFactory;

  /// Whether parameterized resolutions are cached per `(param1, param2)`
  /// pair (`registerCachedFactoryParam` semantics).
  final bool paramCached;

  final Map<(Object?, Object?), T> _paramCache = {};
  final Map<(Object?, Object?), Future<T>> _paramAsyncCache = {};

  /// Whether this registration is a parameterized factory.
  bool get isParamFactory => paramFactory != null || paramAsyncFactory != null;

  Completer<void> _readyCompleter = Completer<void>();
  T? _cachedInstance;
  Future<T>? _asyncFuture;
  bool _disposed = false;
  bool _syncResolutionActive = false;

  /// Whether this descriptor has been disposed.
  bool get isDisposed => _disposed;

  /// Indicates whether a lazy singleton has already been resolved and cached.
  bool get hasInstance => _cachedInstance != null;

  /// The currently cached instance, if any. Used by `signalReady(instance)`
  /// and diagnostics; `null` for uncached lifecycles.
  Object? get cachedInstance => _cachedInstance;

  /// Indicates whether an async lifecycle resolution is in-flight or completed.
  bool get hasAsyncResolution => _asyncFuture != null;

  /// Indicates whether this registration participates in readiness tracking.
  bool get participatesInReadiness =>
      lifecycle == DependencyLifecycle.asyncSingleton || signalsReady;

  /// Indicates whether the descriptor is ready for use.
  ///
  /// Async singletons are ready once their instance is cached; registrations
  /// marked [signalsReady] additionally require a manual `signalReady` call.
  /// Transient factories are always ready.
  bool get isReady {
    switch (lifecycle) {
      case DependencyLifecycle.asyncSingleton:
        return _cachedInstance != null &&
            (!signalsReady || _readyCompleter.isCompleted);
      case DependencyLifecycle.asyncFactory:
      case DependencyLifecycle.factory:
        return true;
      case DependencyLifecycle.singleton:
      case DependencyLifecycle.lazySingleton:
        return (!signalsReady || _readyCompleter.isCompleted) &&
            pendingResult == null;
    }
  }

  /// Completes the manual readiness signal for [signalsReady] registrations.
  void signalReady() {
    if (!signalsReady || _readyCompleter.isCompleted) return;
    _readyCompleter.complete();
  }

  /// Returns a future that completes when this registration is ready.
  ///
  /// When [startAsyncResolution] is true, lazy async singletons begin their
  /// resolution; otherwise only in-flight or cached async work is awaited.
  Future<void> readiness({bool startAsyncResolution = false}) {
    final futures = <Future<void>>[];
    if (lifecycle == DependencyLifecycle.asyncSingleton &&
        (startAsyncResolution || hasAsyncResolution || hasInstance)) {
      futures.add(resolveAsync().then((_) {}));
    }
    if (signalsReady) {
      futures.add(_readyCompleter.future);
    }
    final pending = pendingResult;
    if (pending != null) {
      futures.add(pending);
    }
    if (futures.isEmpty) return Future<void>.value();
    return Future.wait(futures);
  }

  /// Resolves the instance according to its [lifecycle].
  T resolve() {
    _ensureNotDisposed();
    if (lifecycle == DependencyLifecycle.asyncSingleton ||
        lifecycle == DependencyLifecycle.asyncFactory) {
      throw StateError(
        'Dependency ${key.toString()} is asynchronous and must be resolved '
        'with resolveAsync() / getAsync<T>().',
      );
    }
    if (_syncResolutionActive &&
        (lifecycle == DependencyLifecycle.singleton ||
            lifecycle == DependencyLifecycle.lazySingleton)) {
      throw StateError(
        'Circular dependency detected while resolving ${key.toString()}.',
      );
    }

    switch (lifecycle) {
      case DependencyLifecycle.singleton:
      case DependencyLifecycle.lazySingleton:
        if (_cachedInstance != null) return _cachedInstance as T;
        _syncResolutionActive = true;
        try {
          final instance = factory();
          if (!_disposed) {
            _cachedInstance = instance;
            onCreated?.call(instance);
            if (!signalsReady) {
              signalReady();
            }
          }
          return instance;
        } finally {
          _syncResolutionActive = false;
        }
      case DependencyLifecycle.factory:
        final instance = factory();
        onCreated?.call(instance);
        return instance;
      case DependencyLifecycle.asyncSingleton:
      case DependencyLifecycle.asyncFactory:
        throw StateError('unreachable');
    }
  }

  /// Resolves the instance asynchronously.
  Future<T> resolveAsync() {
    _ensureNotDisposed();
    switch (lifecycle) {
      case DependencyLifecycle.asyncSingleton:
        final pending = _asyncFuture;
        if (pending != null) return pending;
        late final Future<T> future;
        future = _resolveAsyncFactory().catchError((Object error) {
          if (identical(_asyncFuture, future)) {
            _asyncFuture = null;
          }
          throw error;
        });
        _asyncFuture = future;
        return future;
      case DependencyLifecycle.asyncFactory:
        return _resolveAsyncFactory();
      case DependencyLifecycle.singleton:
      case DependencyLifecycle.lazySingleton:
      case DependencyLifecycle.factory:
        return Future<T>.value(resolve());
    }
  }

  /// Invokes the async factory and caches singleton resolutions.
  Future<T> _resolveAsyncFactory() async {
    _ensureNotDisposed();
    try {
      final instance = await asyncFactory!();
      if (_disposed) {
        await _runOnDispose(instance);
        throw StateError(
            'Dependency ${key.toString()} was disposed during resolution.');
      }
      if (lifecycle == DependencyLifecycle.asyncSingleton) {
        _cachedInstance = instance;
      }
      onCreated?.call(instance);
      if (!signalsReady) {
        signalReady();
      }
      return instance;
    } catch (_) {
      rethrow;
    }
  }

  /// Clears the cached instance of a lazy singleton while keeping the
  /// registration alive, so the next resolution invokes the factory again.
  ///
  /// Only [DependencyLifecycle.lazySingleton] and
  /// [DependencyLifecycle.asyncSingleton] can be reset. When [disposeHooks]
  /// is true the previous instance's disposal hook runs first; an optional
  /// [disposingFunction] overrides the registered `onDispose` for this reset.
  Future<void> resetLazy({
    bool disposeHooks = true,
    FutureOr<void> Function(T instance)? disposingFunction,
  }) async {
    if (lifecycle != DependencyLifecycle.lazySingleton &&
        lifecycle != DependencyLifecycle.asyncSingleton) {
      throw StateError(
        'Only lazy singletons can be reset. ${key.toString()} uses '
        '${lifecycle.name}.',
      );
    }

    final pending = _asyncFuture;
    var instance = _cachedInstance;
    _cachedInstance = null;
    _asyncFuture = null;
    if (signalsReady) {
      // A reset registration must signal readiness again after recreation.
      _readyCompleter = Completer<void>();
    }

    if (pending != null && instance == null) {
      try {
        instance = await pending;
      } catch (_) {
        instance = null;
      }
    }

    if (disposeHooks && instance != null) {
      await _runOnDispose(instance, disposingFunction);
    }
  }

  /// Resolves a parameterized factory with the given arguments.
  ///
  /// When [paramCached] is true the result is cached per `(param1, param2)`
  /// pair, mirroring `get_it.registerCachedFactoryParam`.
  T resolveParam(Object? param1, Object? param2) {
    _ensureNotDisposed();
    final factory = paramFactory;
    if (factory == null) {
      throw StateError(
          'Dependency ${key.toString()} is not a parameterized factory.');
    }
    final cacheKey = (param1, param2);
    if (paramCached) {
      final cached = _paramCache[cacheKey];
      if (cached != null) return cached;
      final instance = factory(param1, param2);
      _paramCache[cacheKey] = instance;
      onCreated?.call(instance);
      return instance;
    }
    final instance = factory(param1, param2);
    onCreated?.call(instance);
    return instance;
  }

  /// Asynchronously resolves a parameterized factory with the given
  /// arguments, sharing in-flight futures per parameter pair when cached.
  Future<T> resolveParamAsync(Object? param1, Object? param2) {
    _ensureNotDisposed();
    final factory = paramAsyncFactory;
    if (factory == null) {
      throw StateError(
          'Dependency ${key.toString()} is not an async parameterized factory.');
    }
    final cacheKey = (param1, param2);
    if (paramCached) {
      final pending = _paramAsyncCache[cacheKey];
      if (pending != null) return pending;
      late final Future<T> future;
      future = _resolveParamAsyncInner(factory, param1, param2)
          .catchError((Object error) {
        if (identical(_paramAsyncCache[cacheKey], future)) {
          _paramAsyncCache.remove(cacheKey);
        }
        throw error;
      });
      _paramAsyncCache[cacheKey] = future;
      return future;
    }
    return _resolveParamAsyncInner(factory, param1, param2);
  }

  Future<T> _resolveParamAsyncInner(
    Future<T> Function(Object?, Object?) factory,
    Object? param1,
    Object? param2,
  ) async {
    _ensureNotDisposed();
    final instance = await factory(param1, param2);
    if (_disposed) {
      await _runOnDispose(instance);
      throw StateError(
          'Dependency ${key.toString()} was disposed during resolution.');
    }
    onCreated?.call(instance);
    return instance;
  }

  /// Disposes the cached instance and waits for async disposal hooks.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    final pending = _asyncFuture;
    if (pending != null && _cachedInstance == null) {
      try {
        final instance = await pending;
        await _runOnDispose(instance);
      } catch (_) {
        // Resolution failures are surfaced to awaiting callers.
      }
    } else {
      await _runOnDispose(_cachedInstance);
    }

    _cachedInstance = null;
    _asyncFuture = null;
    _paramCache.clear();
    _paramAsyncCache.clear();
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Cannot resolve disposed dependency ${key.toString()}.');
    }
  }

  Future<void> _runOnDispose(
    T? instance, [
    FutureOr<void> Function(T instance)? disposingFunction,
  ]) async {
    if (instance == null) return;
    try {
      final hook = disposingFunction ?? onDispose;
      final FutureOr<void>? result;
      if (hook != null) {
        result = hook(instance);
      } else if (instance is Disposable) {
        result = instance.onDispose();
      } else {
        result = null;
      }
      if (result is Future<void>) {
        await result;
      }
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
