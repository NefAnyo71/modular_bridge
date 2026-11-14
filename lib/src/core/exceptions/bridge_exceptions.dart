import 'dart:async';

import '../annotations.dart';

/// Base sealed exception class for all errors thrown by `modular_bridge`.
///
/// By using a sealed hierarchy, callers can exhaustively pattern-match
/// against all possible framework error conditions.
@immutable()
sealed class BridgeException implements Exception {
  /// Creates a [BridgeException] with a descriptive [message].
  const BridgeException(this.message);

  /// Human-readable explanation of the error.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Sealed base class for all dependency-injection related exceptions.
sealed class BridgeDependencyException extends BridgeException {
  /// Creates a [BridgeDependencyException].
  const BridgeDependencyException(
    super.message, {
    this.type,
    this.instanceName,
  });

  /// The Dart [Type] that triggered the exception.
  final Type? type;

  /// The optional named instance qualifier.
  final String? instanceName;
}

/// Thrown when attempting to resolve a dependency that is not registered.
final class BridgeDependencyNotFoundException
    extends BridgeDependencyException {
  /// Creates a [BridgeDependencyNotFoundException] for the given [type] and optional [instanceName].
  const BridgeDependencyNotFoundException(
    Type type, {
    super.instanceName,
  }) : super(
          'No dependency registered for type \'$type\''
          '${instanceName != null ? ' with name \'$instanceName\'' : ''}. '
          'Ensure the appropriate FeatureModule or dependency registration occurs before lookup.',
          type: type,
        );
}

/// Thrown when attempting to register a duplicate dependency without allowing override.
final class BridgeDependencyAlreadyRegisteredException
    extends BridgeDependencyException {
  /// Creates a [BridgeDependencyAlreadyRegisteredException].
  const BridgeDependencyAlreadyRegisteredException(
    Type type, {
    super.instanceName,
  }) : super(
          'Dependency of type \'$type\''
          '${instanceName != null ? ' with name \'$instanceName\'' : ''} '
          'is already registered. Set `override: true` or invoke `bridge.override<T>()` '
          'if you intentionally wish to replace this registration.',
          type: type,
        );
}

/// Thrown when a synchronous [ModularBridge.get] is used on a dependency that
/// was registered with an async factory.
///
/// Resolve the dependency with `getAsync<T>()` instead.
final class BridgeAsyncDependencyException extends BridgeDependencyException {
  /// Creates a [BridgeAsyncDependencyException] for the given [type].
  // ignore: prefer_const_constructors_in_immutables — interpolated message is not const-evaluable.
  BridgeAsyncDependencyException(Type type)
      : super(
          'Dependency \'$type\' is registered asynchronously and must be '
          'resolved with `getAsync<T>()` instead of `get<T>()`.',
          type: type,
        );
}

/// Thrown when a circular dependency loop is detected during dependency resolution.
final class BridgeCircularDependencyException
    extends BridgeDependencyException {
  /// Creates a [BridgeCircularDependencyException] with the active resolution stack.
  BridgeCircularDependencyException(
    Type type,
    List<Type> resolutionChain,
  ) : super(
          'Circular dependency detected while resolving \'$type\'. '
          'Resolution chain: ${[
            ...resolutionChain,
            type
          ].map((t) => t.toString()).join(' -> ')}.',
          type: type,
        );
}

/// Sealed base class for configuration and environment-related exceptions.
sealed class BridgeConfigException extends BridgeException {
  /// Creates a [BridgeConfigException].
  const BridgeConfigException(
    super.message, {
    this.key,
    this.expectedType,
    this.actualType,
  });

  /// The configuration key that triggered this exception.
  final String? key;

  /// The expected Dart type for the requested configuration key.
  final Type? expectedType;

  /// The actual type encountered in the configuration store.
  final Type? actualType;
}

/// Thrown when a required configuration key is missing from [BridgeConfig].
final class BridgeConfigKeyNotFoundException extends BridgeConfigException {
  /// Creates a [BridgeConfigKeyNotFoundException].
  const BridgeConfigKeyNotFoundException(String key)
      : super(
          'Configuration key \'$key\' was not found in the current BridgeConfig environment. '
          'Ensure it is configured in the environment map or supply a fallback default value.',
          key: key,
        );
}

/// Thrown when a configuration value cannot be cast or converted to the requested type.
final class BridgeConfigTypeMismatchException extends BridgeConfigException {
  /// Creates a [BridgeConfigTypeMismatchException].
  const BridgeConfigTypeMismatchException({
    required String key,
    required Type expectedType,
    required Type actualType,
  }) : super(
          'Configuration value for key \'$key\' is of type \'$actualType\', '
          'but expected type \'$expectedType\'.',
          key: key,
          expectedType: expectedType,
          actualType: actualType,
        );
}

/// Thrown when [ModularBridge.allReady] or [ModularBridge.isReady] exceeds its
/// timeout while dependencies are still pending.
///
/// Carries structured details about which registrations were still pending
/// and which had already become ready.
final class BridgeWaitingTimeOutException extends TimeoutException {
  /// Creates a [BridgeWaitingTimeOutException].
  BridgeWaitingTimeOutException({
    required Duration duration,
    required this.pending,
    required this.ready,
  }) : super(
          'Timed out after ${duration.inMilliseconds}ms waiting for '
          'dependencies to be ready. Pending: '
          '${pending.isEmpty ? 'none' : pending.join(', ')}.',
          duration,
        );

  /// Registration keys that had not become ready when the timeout hit.
  final List<String> pending;

  /// Registration keys that were already ready when the timeout hit.
  final List<String> ready;
}

/// Sealed base class for module lifecycle and registration exceptions.
sealed class BridgeModuleException extends BridgeException {
  /// Creates a [BridgeModuleException].
  const BridgeModuleException(super.message, {this.moduleName});

  /// The module identifier or class name.
  final String? moduleName;
}

/// Thrown when a [FeatureModule] with the same name has already been registered.
final class BridgeModuleAlreadyRegisteredException
    extends BridgeModuleException {
  /// Creates a [BridgeModuleAlreadyRegisteredException].
  const BridgeModuleAlreadyRegisteredException(String moduleName)
      : super(
          'FeatureModule \'$moduleName\' is already registered in ModularBridge.',
          moduleName: moduleName,
        );
}

/// Thrown when an operation targets a [FeatureModule] that is not registered.
final class BridgeModuleNotFoundException extends BridgeModuleException {
  /// Creates a [BridgeModuleNotFoundException].
  const BridgeModuleNotFoundException(String moduleName)
      : super(
          'FeatureModule \'$moduleName\' is not registered in ModularBridge.',
          moduleName: moduleName,
        );
}

/// Thrown when unregistering a [FeatureModule] that other registered modules
/// still declare as a dependency.
final class BridgeModuleInUseException extends BridgeModuleException {
  /// Creates a [BridgeModuleInUseException].
  BridgeModuleInUseException({
    required String moduleName,
    required List<String> dependentModules,
  })  : dependentModules = List.unmodifiable(dependentModules),
        super(
          'FeatureModule \'$moduleName\' cannot be unregistered because it is '
          'required by: ${dependentModules.join(', ')}. Unregister the dependent '
          'modules first or pass `force: true` to unregister anyway.',
          moduleName: moduleName,
        );

  /// Names of the registered modules that depend on the module being unregistered.
  final List<String> dependentModules;
}

/// Thrown when a scope operation targets a [BridgeScope] name that does not
/// exist on the active scope stack or among live scopes.
final class BridgeScopeNotFoundException extends BridgeException {
  /// Creates a [BridgeScopeNotFoundException].
  const BridgeScopeNotFoundException(String scopeName)
      : super(
          'No BridgeScope named \'$scopeName\' exists. Push or create a named '
          'scope before calling dropScope/popScopesTill.',
        );
}

/// Thrown when module dependencies are not satisfied.
final class BridgeModuleMissingDependencyException
    extends BridgeModuleException {
  /// Creates a [BridgeModuleMissingDependencyException].
  const BridgeModuleMissingDependencyException({
    required String moduleName,
    required Type missingDependency,
  }) : super(
          'FeatureModule \'$moduleName\' requires dependency module \'$missingDependency\', '
          'which has not been registered yet.',
          moduleName: moduleName,
        );
}
