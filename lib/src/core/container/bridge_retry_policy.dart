/// Retry policy for asynchronous dependency factories.
///
/// Pass to `registerAsyncSingleton`, `registerSingletonAsync`,
/// `registerLazySingletonAsync`, or `registerFactoryAsync` via the
/// `retryPolicy` parameter. The policy wraps the factory invocation: on
/// failure the container waits [delay] (multiplied by [backoff] for each
/// subsequent retry) and tries again until [maxAttempts] is reached or
/// [retryIf] rejects the error.
///
/// ```dart
/// bridge.registerAsyncSingleton<ApiClient>(
///   () => ApiClient.connect(),
///   retryPolicy: const BridgeRetryPolicy(
///     maxAttempts: 3,
///     delay: Duration(milliseconds: 200),
///     backoff: 2.0,
///   ),
/// );
/// ```
final class BridgeRetryPolicy {
  /// Creates a [BridgeRetryPolicy].
  ///
  /// [maxAttempts] is the total number of factory invocations including the
  /// first — `1` disables retrying. [delay] is the base wait before the first
  /// retry; each further retry waits `delay * backoff^n`. [retryIf] optionally
  /// filters which errors are retried (defaults to retrying everything).
  const BridgeRetryPolicy({
    this.maxAttempts = 3,
    this.delay = Duration.zero,
    this.backoff = 1.0,
    this.retryIf,
  })  : assert(maxAttempts >= 1, 'maxAttempts must be >= 1'),
        assert(backoff >= 0, 'backoff must be >= 0');

  /// Total factory invocations including the first attempt.
  final int maxAttempts;

  /// Base delay before the first retry.
  final Duration delay;

  /// Multiplier applied to [delay] for each subsequent retry.
  final double backoff;

  /// Optional predicate deciding whether a thrown error is retried.
  /// Return `false` to fail immediately.
  final bool Function(Object error)? retryIf;
}
