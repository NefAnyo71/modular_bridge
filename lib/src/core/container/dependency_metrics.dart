import '../annotations.dart';

/// Per-key resolution statistics.
@immutable()
final class DependencyMetricEntry {
  /// Creates a [DependencyMetricEntry].
  const DependencyMetricEntry({
    required this.resolutions,
    required this.cacheHits,
    required this.failures,
    required this.totalMicros,
    required this.maxMicros,
  });

  /// Total resolution attempts.
  final int resolutions;

  /// Attempts served from an already-cached instance.
  final int cacheHits;

  /// Attempts that threw.
  final int failures;

  /// Sum of resolution durations in microseconds.
  final int totalMicros;

  /// Slowest single resolution in microseconds.
  final int maxMicros;

  /// Average resolution duration in microseconds.
  double get averageMicros => resolutions == 0 ? 0 : totalMicros / resolutions;

  /// Cache hit ratio in `[0, 1]`.
  double get cacheHitRatio => resolutions == 0 ? 0 : cacheHits / resolutions;
}

/// Aggregated resolution metrics for a [ModularBridge] container.
///
/// Records every factory invocation across sync, async, and parameterized
/// resolutions — including scope-local registrations. Exposed via
/// `bridge.metrics` and included in `diagnosticsReport()`.
final class DependencyMetrics {
  final Map<String, _MutableEntry> _entries = {};
  final Map<String, _MutableModuleEntry> _moduleEntries = {};
  int _totalResolutions = 0;
  int _totalCacheHits = 0;
  int _totalFailures = 0;

  /// Total resolution attempts across all dependencies.
  int get totalResolutions => _totalResolutions;

  /// Total cache hits across all dependencies.
  int get totalCacheHits => _totalCacheHits;

  /// Total failed resolutions across all dependencies.
  int get totalFailures => _totalFailures;

  /// Overall cache hit ratio in `[0, 1]`.
  double get cacheHitRatio =>
      _totalResolutions == 0 ? 0 : _totalCacheHits / _totalResolutions;

  /// Per-module aggregate counters, keyed by [FeatureModule.name].
  ///
  /// Only registrations made inside a module's `registerDependencies`/`init`
  /// carry an owner; root-level registrations are not attributed to any module.
  Map<String, DependencyMetricEntry> get moduleEntries {
    final sorted = _moduleEntries.values.toList()
      ..sort((a, b) => b.entry.resolutions.compareTo(a.entry.resolutions));
    return Map.unmodifiable({
      for (final e in sorted) e.key: e.entry,
    });
  }

  /// Per-key metric entries, sorted by resolution count descending.
  Map<String, DependencyMetricEntry> get entries {
    final sorted = _entries.values.toList()
      ..sort((a, b) => b.entry.resolutions.compareTo(a.entry.resolutions));
    return Map.unmodifiable({
      for (final e in sorted) e.key: e.entry,
    });
  }

  /// JSON-friendly snapshot for diagnostics and DevTools.
  Map<String, Object?> snapshot() {
    return {
      'totalResolutions': _totalResolutions,
      'totalCacheHits': _totalCacheHits,
      'totalFailures': _totalFailures,
      'cacheHitRatio': cacheHitRatio,
      'byModule': {
        for (final e in moduleEntries.entries)
          e.key: {
            'resolutions': e.value.resolutions,
            'cacheHits': e.value.cacheHits,
            'failures': e.value.failures,
          },
      },
      'entries': {
        for (final e in entries.entries)
          e.key: {
            'resolutions': e.value.resolutions,
            'cacheHits': e.value.cacheHits,
            'failures': e.value.failures,
            'avgMicros': e.value.averageMicros.round(),
            'maxMicros': e.value.maxMicros,
          },
      },
    };
  }

  /// Records a resolution attempt. Called internally by descriptors.
  ///
  /// When [module] is non-null the attempt is also aggregated under that
  /// module's name in [moduleEntries].
  void record(
    String key, {
    required int elapsedMicros,
    required bool cacheHit,
    required bool failed,
    String? module,
  }) {
    _totalResolutions++;
    if (cacheHit) _totalCacheHits++;
    if (failed) _totalFailures++;
    final entry = _entries.putIfAbsent(key, () => _MutableEntry(key));
    entry.record(elapsedMicros, cacheHit: cacheHit, failed: failed);
    if (module != null) {
      _moduleEntries
          .putIfAbsent(module, () => _MutableModuleEntry(module))
          .record(cacheHit: cacheHit, failed: failed);
    }
  }

  /// Resets all counters.
  void reset() {
    _entries.clear();
    _moduleEntries.clear();
    _totalResolutions = 0;
    _totalCacheHits = 0;
    _totalFailures = 0;
  }
}

final class _MutableEntry {
  _MutableEntry(this.key);

  final String key;
  int resolutions = 0;
  int cacheHits = 0;
  int failures = 0;
  int totalMicros = 0;
  int maxMicros = 0;

  DependencyMetricEntry get entry => DependencyMetricEntry(
        resolutions: resolutions,
        cacheHits: cacheHits,
        failures: failures,
        totalMicros: totalMicros,
        maxMicros: maxMicros,
      );

  void record(int micros, {required bool cacheHit, required bool failed}) {
    resolutions++;
    if (cacheHit) cacheHits++;
    if (failed) failures++;
    totalMicros += micros;
    if (micros > maxMicros) maxMicros = micros;
  }
}

final class _MutableModuleEntry {
  _MutableModuleEntry(this.key);

  final String key;
  int resolutions = 0;
  int cacheHits = 0;
  int failures = 0;

  DependencyMetricEntry get entry => DependencyMetricEntry(
        resolutions: resolutions,
        cacheHits: cacheHits,
        failures: failures,
        totalMicros: 0,
        maxMicros: 0,
      );

  void record({required bool cacheHit, required bool failed}) {
    resolutions++;
    if (cacheHit) cacheHits++;
    if (failed) failures++;
  }
}
