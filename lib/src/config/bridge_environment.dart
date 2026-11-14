/// Supported application build environments and flavors.
enum BridgeEnvironment {
  /// Development environment for local testing and debugging.
  dev,

  /// Staging environment mirroring production for QA and integration testing.
  staging,

  /// Live production environment for end users.
  prod;

  /// Returns true if the environment is [BridgeEnvironment.dev].
  bool get isDev => this == BridgeEnvironment.dev;

  /// Returns true if the environment is [BridgeEnvironment.staging].
  bool get isStaging => this == BridgeEnvironment.staging;

  /// Returns true if the environment is [BridgeEnvironment.prod].
  bool get isProd => this == BridgeEnvironment.prod;

  /// Parses a string into a [BridgeEnvironment].
  ///
  /// Matches case-insensitively. E.g. 'dev', 'development', 'stage', 'staging', 'prod', 'production'.
  static BridgeEnvironment fromString(String value) {
    return switch (value.toLowerCase().trim()) {
      'dev' || 'development' => BridgeEnvironment.dev,
      'staging' || 'stage' || 'test' => BridgeEnvironment.staging,
      'prod' || 'production' => BridgeEnvironment.prod,
      _ => throw ArgumentError.value(
          value,
          'value',
          'Unsupported environment string. Supported values: dev, staging, prod',
        ),
    };
  }
}
