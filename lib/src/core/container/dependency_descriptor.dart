import 'package:flutter/foundation.dart';

/// Defines the lifetime and instantiation strategy of a registered dependency.
enum DependencyLifecycle {
  /// Instantiated immediately and cached as a single instance for the lifetime of the container.
  singleton,

  /// Instantiated on first access via a factory function and subsequently cached.
  lazySingleton,

  /// A brand new instance is created every time the dependency is requested.
  factory,
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
    required this.factory,
    T? instance,
    this.ownerModuleName,
    this.onDispose,
  }) : _cachedInstance = instance;

  /// The unique lookup key.
  final DependencyKey key;

  /// The lifecycle strategy for this dependency.
  final DependencyLifecycle lifecycle;

  /// Factory function that produces an instance of [T].
  final T Function() factory;

  /// The optional module name that owns this dependency registration.
  final String? ownerModuleName;

  /// Optional hook executed when this dependency is unregistered or container reset.
  final void Function(T instance)? onDispose;

  T? _cachedInstance;

  /// Indicates whether a lazy singleton has already been resolved and cached.
  bool get hasInstance => _cachedInstance != null;

  /// Resolves the instance according to its [lifecycle].
  T resolve() {
    switch (lifecycle) {
      case DependencyLifecycle.singleton:
      case DependencyLifecycle.lazySingleton:
        return _cachedInstance ??= factory();
      case DependencyLifecycle.factory:
        return factory();
    }
  }

  /// Disposes the cached instance, executing [onDispose] if provided.
  void dispose() {
    if (_cachedInstance != null) {
      try {
        onDispose?.call(_cachedInstance as T);
      } catch (e, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: e,
            stack: stackTrace,
            library: 'modular_bridge',
            context: ErrorDescription('While disposing dependency ${key.toString()}'),
          ),
        );
      } finally {
        _cachedInstance = null;
      }
    }
  }
}

