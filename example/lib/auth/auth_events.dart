import 'package:modular_bridge/modular_bridge.dart';

/// Sealed hierarchy of authentication domain events.
sealed class AuthEvent extends BridgeEvent {
  AuthEvent();
}

/// Dispatched when a user successfully authenticates.
final class UserLoggedInEvent extends AuthEvent {
  UserLoggedInEvent({
    required this.userId,
    required this.email,
  });

  final String userId;
  final String email;

  @override
  String toString() => 'UserLoggedInEvent(userId: $userId, email: $email)';
}

/// Dispatched when the active session is terminated or invalidated.
final class UserLoggedOutEvent extends AuthEvent {
  UserLoggedOutEvent({required this.userId});

  final String userId;

  @override
  String toString() => 'UserLoggedOutEvent(userId: $userId)';
}

