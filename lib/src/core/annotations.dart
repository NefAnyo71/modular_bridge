/// Marker annotations mirroring the subset of `package:flutter/foundation.dart`
/// metadata used by `modular_bridge`, so the core library stays free of any
/// Flutter SDK dependency and can run in pure Dart environments (CLI tools,
/// backend services, `dart test`).
//
// Note: bare `@immutable`-style annotations are rejected by recent analyzers
// (`no_annotation_constructor_arguments`), so use the `@immutable()` form.
library;

// ignore_for_file: camel_case_types

/// Annotation for a method that must be called by subclasses.
///
/// Informational marker matching `package:meta`'s `mustCallSuper`; the
/// analyzer does not enforce it in pure Dart projects.
class mustCallSuper {
  const mustCallSuper();
}

/// Annotation for a member that is only visible for testing.
///
/// Informational marker matching `package:meta`'s `visibleForTesting`.
class visibleForTesting {
  const visibleForTesting();
}

/// Annotation for a class whose instances must not be mutated.
///
/// All public fields must be `final` and the class should not expose
/// mutating methods. Informational marker matching
/// `package:flutter/foundation.dart`'s `immutable`.
class immutable {
  const immutable();
}

/// Annotation for a member that should only be used inside the declaring
/// library or by subclasses.
///
/// Informational marker matching `package:meta`'s `protected`.
class protected {
  const protected();
}

/// Whether the current isolate is running in debug mode.
///
/// Mirrors `kDebugMode` semantics without depending on Flutter: returns
/// `false` only in ahead-of-time product builds (`dart.vm.product`), `true`
/// in JIT/debug/test runs.
const bool kDebugMode = !bool.fromEnvironment('dart.vm.product');
