import 'dart:async';
import '../core/exceptions/bridge_exceptions.dart';
import 'bridge_environment.dart';

/// Manages type-safe application configurations and environment flavors.
///
/// Supports runtime hot-switching between [BridgeEnvironment.dev],
/// [BridgeEnvironment.staging], and [BridgeEnvironment.prod], with instant
/// notification dispatch to listeners.
class BridgeConfig {
  /// Creates a [BridgeConfig] initialized with an [environment], optional
  /// [commonValues], and per-environment [environmentValues].
  BridgeConfig({
    required BridgeEnvironment environment,
    Map<String, dynamic> commonValues = const {},
    Map<BridgeEnvironment, Map<String, dynamic>> environmentValues = const {},
  })  : _environment = environment,
        _commonValues = Map<String, dynamic>.from(commonValues),
        _environmentValues = {
          for (final entry in environmentValues.entries)
            entry.key: Map<String, dynamic>.from(entry.value),
        } {
    _rebuildActiveConfig();
  }

  BridgeEnvironment _environment;
  final Map<String, dynamic> _commonValues;
  final Map<BridgeEnvironment, Map<String, dynamic>> _environmentValues;
  final Map<String, dynamic> _activeConfig = <String, dynamic>{};
  final Map<String, dynamic> _runtimeOverrides = <String, dynamic>{};
  final StreamController<BridgeEnvironment> _envStreamController =
      StreamController<BridgeEnvironment>.broadcast(sync: true);
  final StreamController<void> _changeController =
      StreamController<void>.broadcast(sync: true);
  bool _isDisposed = false;

  /// The active application environment.
  BridgeEnvironment get environment => _environment;

  /// Whether [dispose] has been called on this instance.
  bool get isDisposed => _isDisposed;

  /// Stream emitting the new [BridgeEnvironment] whenever [switchEnvironment] is invoked.
  Stream<BridgeEnvironment> get onEnvironmentChanged =>
      _envStreamController.stream;

  /// Stream emitting whenever any configuration value changes:
  /// [set], [setAll], [remove], or [switchEnvironment].
  Stream<void> get onChanged => _changeController.stream;

  /// Returns an unmodifiable snapshot of currently active key-value pairs.
  Map<String, dynamic> get currentValues =>
      Map<String, dynamic>.unmodifiable(_activeConfig);

  /// Checks if a configuration key exists in the active configuration.
  bool hasKey(String key) => _activeConfig.containsKey(key);

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('Cannot modify a disposed BridgeConfig.');
    }
  }

  /// Rebuilds the combined configuration map for the active environment.
  ///
  /// Layer order (lowest to highest precedence): common values,
  /// environment-specific values, then persistent [set]/[setAll] runtime overrides.
  void _rebuildActiveConfig() {
    _activeConfig
      ..clear()
      ..addAll(_commonValues);
    final envSpecific = _environmentValues[_environment];
    if (envSpecific != null) {
      _activeConfig.addAll(envSpecific);
    }
    _activeConfig.addAll(_runtimeOverrides);
  }

  /// Resolves the raw value for [key].
  ///
  /// Returns `(found: false, value: defaultValue)` when the key is absent and
  /// a non-null [defaultValue] was supplied; otherwise throws
  /// [BridgeConfigKeyNotFoundException].
  ({bool found, dynamic value}) _lookup(String key, dynamic defaultValue) {
    if (_activeConfig.containsKey(key)) {
      return (found: true, value: _activeConfig[key]);
    }
    if (defaultValue != null) {
      return (found: false, value: defaultValue);
    }
    throw BridgeConfigKeyNotFoundException(key);
  }

  BridgeConfigTypeMismatchException _typeMismatch(
    String key,
    Type expectedType,
    dynamic value,
  ) =>
      BridgeConfigTypeMismatchException(
        key: key,
        expectedType: expectedType,
        actualType: value.runtimeType,
      );

  String _asString(String key, dynamic value) {
    if (value is String) return value;
    // Coerce primitives so env-style configs ('8080', true) stay ergonomic.
    if (value is num || value is bool) return value.toString();
    throw _typeMismatch(key, String, value);
  }

  int _asInt(String key, dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw _typeMismatch(key, int, value);
  }

  double _asDouble(String key, dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw _typeMismatch(key, double, value);
  }

  bool _asBool(String key, dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase().trim();
      if (lower == 'true' || lower == '1') return true;
      if (lower == 'false' || lower == '0') return false;
    }
    throw _typeMismatch(key, bool, value);
  }

  Duration _asDuration(String key, dynamic value) {
    if (value is Duration) return value;
    if (value is int) return Duration(milliseconds: value);
    if (value is String) {
      final parsedMs = int.tryParse(value);
      if (parsedMs != null) return Duration(milliseconds: parsedMs);
    }
    throw _typeMismatch(key, Duration, value);
  }

  Uri _asUri(String key, dynamic value) {
    if (value is Uri) return value;
    if (value is String) {
      final parsed = Uri.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw _typeMismatch(key, Uri, value);
  }

  /// Switches the active environment at runtime (hot-switch) and notifies listeners.
  ///
  /// Optionally merges [runtimeOverrides] into the configuration. Overrides
  /// are persisted and remain active across subsequent environment switches
  /// until removed via [remove].
  void switchEnvironment(
    BridgeEnvironment newEnvironment, {
    Map<String, dynamic>? runtimeOverrides,
  }) {
    _ensureNotDisposed();
    final envChanged = _environment != newEnvironment;
    if (!envChanged && runtimeOverrides == null) return;

    _environment = newEnvironment;
    if (runtimeOverrides != null) {
      _runtimeOverrides.addAll(runtimeOverrides);
    }
    _rebuildActiveConfig();

    // Only emit the environment event when the environment actually changed;
    // runtime-only updates still notify via onChanged.
    if (envChanged) {
      _envStreamController.add(_environment);
    }
    _changeController.add(null);
  }

  /// Sets or updates a single configuration value.
  ///
  /// The value persists across environment switches as a runtime override.
  void set(String key, dynamic value) {
    _ensureNotDisposed();
    _runtimeOverrides[key] = value;
    _activeConfig[key] = value;
    _changeController.add(null);
  }

  /// Sets multiple configuration values.
  ///
  /// The values persist across environment switches as runtime overrides.
  void setAll(Map<String, dynamic> values) {
    _ensureNotDisposed();
    _runtimeOverrides.addAll(values);
    _activeConfig.addAll(values);
    _changeController.add(null);
  }

  /// Removes a runtime override for [key].
  ///
  /// If the key was defined in [commonValues] or the active environment's
  /// values, the underlying configured value becomes visible again.
  /// Returns `true` if an override was removed.
  bool remove(String key) {
    _ensureNotDisposed();
    final removed = _runtimeOverrides.remove(key) != null;
    if (removed) {
      _rebuildActiveConfig();
      _changeController.add(null);
    }
    return removed;
  }

  /// Retrieves a strictly typed configuration value for [key].
  ///
  /// If [defaultValue] is provided and [key] does not exist, [defaultValue] is returned.
  /// Throws [BridgeConfigKeyNotFoundException] if [key] is absent and no default is given.
  /// Throws [BridgeConfigTypeMismatchException] if the value exists but is not of type [T].
  T get<T>(String key, {T? defaultValue}) {
    final result = _lookup(key, defaultValue);
    if (!result.found) return result.value as T;
    final value = result.value;
    if (value is T) return value;
    throw _typeMismatch(key, T, value);
  }

  /// Attempts to retrieve a value of type [T], returning `null` if the key
  /// is not present or if a type mismatch occurs.
  T? tryGet<T>(String key) {
    if (!_activeConfig.containsKey(key)) return null;
    final value = _activeConfig[key];
    return value is T ? value : null;
  }

  /// Retrieves a string configuration value for [key].
  ///
  /// Coerces primitive values (num, bool) to [String] when possible.
  String getString(String key, {String? defaultValue}) {
    final result = _lookup(key, defaultValue);
    if (!result.found) return result.value as String;
    return _asString(key, result.value);
  }

  /// Retrieves an integer configuration value for [key].
  ///
  /// Automatically parses integer values from strings or numeric types.
  int getInt(String key, {int? defaultValue}) {
    final result = _lookup(key, defaultValue);
    if (!result.found) return result.value as int;
    return _asInt(key, result.value);
  }

  /// Retrieves a double precision floating point configuration value for [key].
  double getDouble(String key, {double? defaultValue}) {
    final result = _lookup(key, defaultValue);
    if (!result.found) return result.value as double;
    return _asDouble(key, result.value);
  }

  /// Retrieves a boolean configuration value for [key].
  ///
  /// Supports raw booleans as well as case-insensitive `'true'` / `'false'` strings.
  bool getBool(String key, {bool? defaultValue}) {
    final result = _lookup(key, defaultValue);
    if (!result.found) return result.value as bool;
    return _asBool(key, result.value);
  }

  /// Retrieves a [Duration] configuration value for [key].
  ///
  /// Supports:
  /// - Direct [Duration] instances
  /// - [int] representing milliseconds
  /// - [String] representing integer milliseconds
  Duration getDuration(String key, {Duration? defaultValue}) {
    final result = _lookup(key, defaultValue);
    if (!result.found) return result.value as Duration;
    return _asDuration(key, result.value);
  }

  /// Retrieves an unmodifiable [Map] configuration value for [key].
  ///
  /// Throws [BridgeConfigKeyNotFoundException] if [key] is absent and no
  /// [defaultValue] is given, and [BridgeConfigTypeMismatchException] if the
  /// stored value is not a [Map].
  Map<String, dynamic> getMap(String key,
      {Map<String, dynamic>? defaultValue}) {
    final result = _lookup(key, defaultValue);
    if (!result.found) {
      return Map<String, dynamic>.unmodifiable(result.value as Map);
    }
    final value = result.value;
    if (value is Map) {
      return Map<String, dynamic>.unmodifiable(
          Map<String, dynamic>.from(value));
    }
    throw _typeMismatch(key, Map<String, dynamic>, value);
  }

  /// Decodes a nested map stored under [key] into a typed object [T] using
  /// [decoder].
  ///
  /// ```dart
  /// final api = config.getSection<ApiConfig>(
  ///   'api',
  ///   (m) => ApiConfig(baseUrl: m['baseUrl'] as String),
  /// );
  /// ```
  ///
  /// Throws [BridgeConfigKeyNotFoundException] if [key] is absent.
  T getSection<T>(
    String key,
    T Function(Map<String, dynamic> values) decoder,
  ) {
    return decoder(getMap(key));
  }

  /// Retrieves a [Uri] configuration value for [key].
  ///
  /// Supports direct [Uri] instances or parsable URI strings.
  Uri getUri(String key, {Uri? defaultValue}) {
    final result = _lookup(key, defaultValue);
    if (!result.found) return result.value as Uri;
    return _asUri(key, result.value);
  }

  /// Disposes the internal environment stream controller.
  ///
  /// Reads remain available after disposal; mutating methods
  /// ([set], [setAll], [switchEnvironment]) throw a [StateError].
  /// Calling [dispose] more than once is a no-op.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _envStreamController.close();
    _changeController.close();
  }
}
