import 'dart:async';
import 'dart:developer' as developer;

import 'modular_bridge_container.dart';

/// Describes a single dependency resolution intercepted by
/// [BridgeResolutionInterceptor]s registered on a [ModularBridge].
///
/// Interceptors observe every public resolution entry point:
/// `get`, `getAsync`, `getParam`, and `getParamAsync` — including
/// resolutions that fall through [BridgeScope] hierarchies. Internal
/// bookkeeping resolutions (`dependsOn` orchestration, `warmup`,
/// `getAll`/`getAllAsync` bulk lookups) are not intercepted.
final class BridgeResolutionRequest {
  /// Creates a [BridgeResolutionRequest].
  const BridgeResolutionRequest({
    required this.bridge,
    required this.type,
    this.instanceName,
    this.arguments = const [],
    required this.isAsync,
  });

  /// The bridge performing the resolution.
  final ModularBridge bridge;

  /// The Dart [Type] being resolved.
  final Type type;

  /// The optional named-instance qualifier, if any.
  final String? instanceName;

  /// Positional arguments for parameterized resolutions
  /// (`getParam`/`getParamAsync`); empty for plain lookups.
  final List<Object?> arguments;

  /// Whether the resolution was initiated through an async entry point
  /// (`getAsync`, `getParamAsync`). Interceptors may return a [Future]
  /// only when this is `true`; on the synchronous path a returned
  /// [Future] raises [BridgeAsyncInterceptorException].
  final bool isAsync;
}

/// Performs the remainder of a resolution chain.
///
/// Calling [BridgeResolutionNext] invokes the next interceptor, or the
/// actual container resolution when the last interceptor delegates.
/// A middleware may choose not to call `next` at all to short-circuit
/// the resolution (decorator/fallback pattern).
typedef BridgeResolutionNext = FutureOr<Object?> Function();

/// Middleware that wraps a single dependency resolution.
///
/// Interceptors run onion-style in registration order: the first added
/// interceptor is outermost. Each interceptor receives the
/// [BridgeResolutionRequest] and a [BridgeResolutionNext] closure; it may
/// inspect/modify the outcome, substitute a different value, throw, or
/// delegate via `next()`.
///
/// On synchronous resolutions (`get`, `getParam`) the interceptor must
/// return the resolved value directly — returning a [Future] throws
/// [BridgeAsyncInterceptorException]. Async entry points accept either
/// plain values or futures.
typedef BridgeResolutionInterceptor = FutureOr<Object?> Function(
  BridgeResolutionRequest request,
  BridgeResolutionNext next,
);

/// Timing details for a single intercepted resolution, delivered to
/// [BridgeInterceptors.timing] callbacks.
final class BridgeResolutionTiming {
  /// Creates a [BridgeResolutionTiming].
  const BridgeResolutionTiming({
    required this.request,
    required this.elapsed,
    required this.succeeded,
  });

  /// The resolution that was measured.
  final BridgeResolutionRequest request;

  /// Wall-clock time spent inside `next()` (including nested resolutions).
  final Duration elapsed;

  /// Whether the resolution completed without throwing.
  final bool succeeded;
}

/// Ready-made [BridgeResolutionInterceptor] factories for common concerns.
///
/// ```dart
/// bridge.addResolutionInterceptor(BridgeInterceptors.logging());
/// bridge.addResolutionInterceptor(
///   BridgeInterceptors.timing((t) => metrics.record(t.request.type, t.elapsed)),
/// );
/// ```
abstract final class BridgeInterceptors {
  BridgeInterceptors._();

  /// Returns an interceptor that logs every resolution — type, optional
  /// instance name, duration, and outcome — through [log] (defaults to
  /// `dart:developer.log`).
  ///
  /// Works on both synchronous and asynchronous resolution paths.
  static BridgeResolutionInterceptor logging({
    void Function(String message)? log,
  }) {
    final sink = log ?? developer.log;
    return (request, next) {
      final label = request.instanceName == null
          ? '${request.type}'
          : '${request.type}(name: ${request.instanceName})';
      final sw = Stopwatch()..start();
      void report(Object? error) {
        sink('$label ${error == null ? 'resolved' : 'FAILED'} in '
            '${sw.elapsedMicroseconds}µs'
            '${error == null ? '' : ': $error'}');
      }

      try {
        final result = next();
        if (result is Future<Object?>) {
          return result.then((value) {
            report(null);
            return value;
          }, onError: (Object error, StackTrace stackTrace) {
            report(error);
            Error.throwWithStackTrace(error, stackTrace);
          });
        }
        report(null);
        return result;
      } catch (error) {
        report(error);
        rethrow;
      }
    };
  }

  /// Returns an interceptor that reports a [BridgeResolutionTiming] for
  /// every resolution to [onTiming].
  ///
  /// Unlike [logging], the callback receives structured data so callers can
  /// aggregate metrics themselves.
  static BridgeResolutionInterceptor timing(
    void Function(BridgeResolutionTiming timing) onTiming,
  ) {
    return (request, next) {
      final sw = Stopwatch()..start();
      void report(Object? error) {
        try {
          onTiming(BridgeResolutionTiming(
            request: request,
            elapsed: sw.elapsed,
            succeeded: error == null,
          ));
        } catch (_) {
          // Metric callbacks must never break resolution.
        }
      }

      try {
        final result = next();
        if (result is Future<Object?>) {
          return result.then((value) {
            report(null);
            return value;
          }, onError: (Object error, StackTrace stackTrace) {
            report(error);
            Error.throwWithStackTrace(error, stackTrace);
          });
        }
        report(null);
        return result;
      } catch (error) {
        report(error);
        rethrow;
      }
    };
  }
}