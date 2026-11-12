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
  final StreamController<BridgeEnvironment> _envStreamController =
      StreamController<BridgeEnvironment>.broadcast(sync: true);

  /// The active application environment.
  BridgeEnvironment get environment => _environment;

  /// Stream emitting the new [BridgeEnvironment] whenever [switchEnvironment] is invoked.
  Stream<BridgeEnvironment> get onEnvironmentChanged =>
      _envStreamController.stream;

  /// Returns an unmodifiable snapshot of currently active key-value pairs.
  Map<String, dynamic> get currentValues =>
      Map<String, dynamic>.unmodifiable(_activeConfig);

  /// Checks if a configuration key exists in the active configuration.
  bool hasKey(String key) => _activeConfig.containsKey(key);

  /// Rebuilds the combined configuration map for the active environment.
  void _rebuildActiveConfig() {
    _activeConfig.clear();
    _activeConfig.addAll(_commonValues);
    final envSpecific = _environmentValues[_environment];
    if (envSpecific != null) {
      _activeConfig.addAll(envSpecific);
    }
  }

  /// Switches the active environment at runtime (hot-switch) and notifies listeners.
  ///
  /// Optionally merges [runtimeOverrides] into the new active environment config.
  void switchEnvironment(
    BridgeEnvironment newEnvironment, {
    Map<String, dynamic>? runtimeOverrides,
  }) {
    if (_environment == newEnvironment && runtimeOverrides == null) return;

    _environment = newEnvironment;
    _rebuildActiveConfig();

    if (runtimeOverrides != null) {
      _activeConfig.addAll(runtimeOverrides);
    }

    _envStreamController.add(_environment);
  }

  /// Sets or updates a single configuration value in the active environment.
  void set(String key, dynamic value) {
    _activeConfig[key] = value;
  }

  /// Sets multiple configuration values in the active environment.
  void setAll(Map<String, dynamic> values) {
    _activeConfig.addAll(values);
  }

  /// Retrieves a strictly typed configuration value for [key].
  ///
  /// If [defaultValue] is provided and [key] does not exist, [defaultValue] is returned.
  /// Throws [BridgeConfigKeyNotFoundException] if [key] is absent and no default is given.
  /// Throws [BridgeConfigTypeMismatchException] if the value exists but is not of type [T].
  T get<T>(String key, {T? defaultValue}) {
    if (!_activeConfig.containsKey(key)) {
      if (defaultValue != null) {
        return defaultValue;
      }
      throw BridgeConfigKeyNotFoundException(key);
    }

    final value = _activeConfig[key];
    if (value is T) {
      return value;
    }

    throw BridgeConfigTypeMismatchException(
      key: key,
      expectedType: T,
      actualType: value.runtimeType,
    );
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
    if (!_activeConfig.containsKey(key)) {
      if (defaultValue != null) return defaultValue;
      throw BridgeConfigKeyNotFoundException(key);
    }
    final value = _activeConfig[key];
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();

    throw BridgeConfigTypeMismatchException(
      key: key,
      expectedType: String,
      actualType: value.runtimeType,
    );
  }

  /// Retrieves an integer configuration value for [key].
  ///
  /// Automatically parses integer values from strings or numeric types.
  int getInt(String key, {int? defaultValue}) {
    if (!_activeConfig.containsKey(key)) {
      if (defaultValue != null) return defaultValue;
      throw BridgeConfigKeyNotFoundException(key);
    }
    final value = _activeConfig[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }

    throw BridgeConfigTypeMismatchException(
      key: key,
      expectedType: int,
      actualType: value.runtimeType,
    );
  }

  /// Retrieves a double precision floating point configuration value for [key].
  double getDouble(String key, {double? defaultValue}) {
    if (!_activeConfig.containsKey(key)) {
      if (defaultValue != null) return defaultValue;
      throw BridgeConfigKeyNotFoundException(key);
    }
    final value = _activeConfig[key];
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }

    throw BridgeConfigTypeMismatchException(
      key: key,
      expectedType: double,
      actualType: value.runtimeType,
    );
  }

  /// Retrieves a boolean configuration value for [key].
  ///
  /// Supports raw booleans as well as case-insensitive `'true'` / `'false'` strings.
  bool getBool(String key, {bool? defaultValue}) {
    if (!_activeConfig.containsKey(key)) {
      if (defaultValue != null) return defaultValue;
      throw BridgeConfigKeyNotFoundException(key);
    }
    final value = _activeConfig[key];
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase().trim();
      if (lower == 'true' || lower == '1') return true;
      if (lower == 'false' || lower == '0') return false;
    }

    throw BridgeConfigTypeMismatchException(
      key: key,
      expectedType: bool,
      actualType: value.runtimeType,
    );
  }

  /// Retrieves a [Duration] configuration value for [key].
  ///
  /// Supports:
  /// - Direct [Duration] instances
  /// - [int] representing milliseconds
  /// - [String] representing integer milliseconds
  Duration getDuration(String key, {Duration? defaultValue}) {
    if (!_activeConfig.containsKey(key)) {
      if (defaultValue != null) return defaultValue;
      throw BridgeConfigKeyNotFoundException(key);
    }
    final value = _activeConfig[key];
    if (value is Duration) return value;
    if (value is int) return Duration(milliseconds: value);
    if (value is String) {
      final parsedMs = int.tryParse(value);
      if (parsedMs != null) return Duration(milliseconds: parsedMs);
    }

    throw BridgeConfigTypeMismatchException(
      key: key,
      expectedType: Duration,
      actualType: value.runtimeType,
    );
  }

  /// Retrieves a [Uri] configuration value for [key].
  ///
  /// Supports direct [Uri] instances or parsable URI strings.
  Uri getUri(String key, {Uri? defaultValue}) {
    if (!_activeConfig.containsKey(key)) {
      if (defaultValue != null) return defaultValue;
      throw BridgeConfigKeyNotFoundException(key);
    }
    final value = _activeConfig[key];
    if (value is Uri) return value;
    if (value is String) {
      final parsed = Uri.tryParse(value);
      if (parsed != null) return parsed;
    }

    throw BridgeConfigTypeMismatchException(
      key: key,
      expectedType: Uri,
      actualType: value.runtimeType,
    );
  }

  /// Disposes the internal environment stream controller.
  void dispose() {
    _envStreamController.close();
  }
}
