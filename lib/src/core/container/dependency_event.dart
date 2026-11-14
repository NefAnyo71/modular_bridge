import '../annotations.dart';
import 'bridge_scope.dart';

/// Lifecycle kind of a dependency registration change.
enum DependencyChangeKind {
  /// A new registration was added to a scope or the root registry.
  registered,

  /// A registration was explicitly unregistered or removed by a scope reset.
  unregistered,
}

/// Event emitted on [ModularBridge.onDependencyEvents] whenever a
/// registration is added or removed in any scope or the root registry.
@immutable()
final class DependencyRegistrationEvent {
  /// Creates a [DependencyRegistrationEvent].
  const DependencyRegistrationEvent({
    required this.kind,
    required this.info,
    this.scopeName,
  });

  /// What happened to the registration.
  final DependencyChangeKind kind;

  /// Snapshot of the registration metadata at event time.
  final DependencyInfo info;

  /// Name of the owning scope, if any.
  final String? scopeName;

  @override
  String toString() => 'DependencyRegistrationEvent(${kind.name}, ${info.key}'
      '${scopeName == null ? '' : ' in $scopeName'})';
}

/// Interface for instances that want to be notified when a scope-level
/// registration shadows (or stops shadowing) them.
///
/// When a [BridgeScope] resolves a dependency whose key is also registered
/// with a cached instance below it in the hierarchy, the lower instance's
/// [onGetShadowed] is invoked once with the shadowing instance. When the
/// scope is disposed or reset, [onLeaveShadow] is invoked so the instance
/// can restore shadowed state.
abstract class ShadowChangeHandlers {
  /// Called when another registration starts shadowing this instance.
  void onGetShadowed(Object? shadowingInstance);

  /// Called when the shadowing registration is removed.
  void onLeaveShadow(Object? shadowedInstance);
}
