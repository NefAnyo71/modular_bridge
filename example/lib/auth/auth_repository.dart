import '../core/core_module.dart';
import 'auth_events.dart';
import 'package:modular_bridge/modular_bridge.dart';

/// Contract for authentication operations.
abstract class AuthRepository {
  String? get currentEmail;
  bool get isAuthenticated;
  Future<void> login(String email, String password);
  Future<void> logout();
}

/// Concrete production implementation of [AuthRepository].
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required this.apiClient,
    required this.logger,
    required this.bridge,
  });

  final ApiClient apiClient;
  final LoggingService logger;
  final ModularBridge bridge;

  String? _currentEmail;

  @override
  String? get currentEmail => _currentEmail;

  @override
  bool get isAuthenticated => _currentEmail != null;

  @override
  Future<void> login(String email, String password) async {
    logger.log('Authenticating $email against ${apiClient.baseUrl}...');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _currentEmail = email;

    // Broadcast domain event to decoupled modules
    bridge.publish(UserLoggedInEvent(userId: 'usr_789', email: email));
  }

  @override
  Future<void> logout() async {
    final email = _currentEmail ?? 'unknown';
    logger.log('Logging out user $email...');
    _currentEmail = null;

    // Broadcast logout event
    bridge.publish(UserLoggedOutEvent(userId: 'usr_789'));
  }
}

/// Mock implementation for unit tests or offline demonstration.
class MockAuthRepository implements AuthRepository {
  String? _email;

  @override
  String? get currentEmail => _email;

  @override
  bool get isAuthenticated => _email != null;

  @override
  Future<void> login(String email, String password) async {
    _email = '[MOCK] $email';
    ModularBridge.I.publish(
      UserLoggedInEvent(userId: 'mock_user', email: _email!),
    );
  }

  @override
  Future<void> logout() async {
    _email = null;
    ModularBridge.I.publish(UserLoggedOutEvent(userId: 'mock_user'));
  }
}

