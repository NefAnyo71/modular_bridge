import 'dart:developer' as developer;

/// A single error captured from a fire-and-forget callback inside
/// `modular_bridge` (dispose hooks, event callbacks, config bindings, ...).
final class BridgeErrorReport {
  /// Creates a [BridgeErrorReport].
  const BridgeErrorReport({
    required this.exception,
    this.stackTrace,
    this.library = 'modular_bridge',
    this.context,
  });

  /// The thrown error or exception object.
  final Object exception;

  /// The stack trace captured at the throw site, if available.
  final StackTrace? stackTrace;

  /// Logical library name the error originated from.
  final String library;

  /// Human-readable description of what was running when the error occurred.
  final String? context;

  @override
  String toString() {
    final buffer = StringBuffer('$library: $exception');
    if (context != null) buffer.write(' ($context)');
    return buffer.toString();
  }
}

/// Contract for sinks that receive [BridgeErrorReport]s produced by
/// `modular_bridge` internals.
///
/// Implement this to forward framework errors to a crash reporter
/// (Sentry, Firebase Crashlytics, ...), a logging pipeline, or a test
/// harness.
abstract interface class BridgeErrorReporter {
  /// Handles a single [report]. Implementations must not throw.
  void report(BridgeErrorReport report);
}

/// Default [BridgeErrorReporter] that forwards reports to
/// `dart:developer.log`, making them visible in DevTools and `flutter logs`.
final class DeveloperLogBridgeErrorReporter implements BridgeErrorReporter {
  /// Creates a [DeveloperLogBridgeErrorReporter].
  const DeveloperLogBridgeErrorReporter();

  @override
  void report(BridgeErrorReport report) {
    developer.log(
      report.toString(),
      name: report.library,
      error: report.exception,
      stackTrace: report.stackTrace,
    );
  }
}

/// Process-wide [BridgeErrorReporter] used by all fire-and-forget callbacks.
///
/// Defaults to [DeveloperLogBridgeErrorReporter]. Replace it during app
/// startup (or in tests) to route framework errors elsewhere:
///
/// ```dart
/// bridgeErrorReporter = MyCrashReporterBridgeErrorReporter();
/// ```
///
/// The setter never throws; a faulty reporter is swallowed to avoid
/// breaking framework internals.
BridgeErrorReporter bridgeErrorReporter =
    const DeveloperLogBridgeErrorReporter();

/// Reports [error] to the active [bridgeErrorReporter].
///
/// This is the pure-Dart replacement for `FlutterError.reportError` used
/// throughout `modular_bridge`. It never throws — reporter failures are
/// ignored so error handling itself cannot break callers.
void reportBridgeError(
  Object error,
  StackTrace stackTrace, {
  String library = 'modular_bridge',
  String? context,
}) {
  try {
    bridgeErrorReporter.report(
      BridgeErrorReport(
        exception: error,
        stackTrace: stackTrace,
        library: library,
        context: context,
      ),
    );
  } catch (_) {
    // A broken reporter must never break framework internals.
  }
}
