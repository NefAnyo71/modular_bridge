import 'package:flutter/foundation.dart';

/// Base class for all domain and cross-module events in `modular_bridge`.
///
/// Modules can define event subclasses to broadcast changes without coupling
/// consumers to concrete implementation details.
///
/// Example:
/// ```dart
/// final class UserLoggedOutEvent extends BridgeEvent {
///   const UserLoggedOutEvent({required this.userId, required this.reason});
///   final String userId;
///   final String reason;
/// }
/// ```
@immutable
abstract class BridgeEvent {
  /// Creates a [BridgeEvent] with an automatic [timestamp].
  BridgeEvent() : timestamp = DateTime.now();

  /// Creates a [BridgeEvent] with an explicit [timestamp].
  const BridgeEvent.withTimestamp(this.timestamp);

  /// The timestamp when the event was generated.
  final DateTime timestamp;

  @override
  String toString() => '$runtimeType(timestamp: $timestamp)';
}
