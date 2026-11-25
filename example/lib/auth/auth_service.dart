import 'package:flutter/foundation.dart';
import 'package:modular_bridge/modular_bridge.dart';

import '../core/core_module.dart';
import 'auth_events.dart';

/// Profile data for the signed-in user.
///
/// Depends eagerly on [AuthService] — safe because [AuthService] only holds
/// a [Lazy] reference back, which is what breaks the circular dependency.
class UserProfileService {
  UserProfileService(this._auth);

  final AuthService _auth;

  String get displayName =>
      _auth.currentEmail == null ? 'Guest' : 'User: ${_auth.currentEmail}';

  String get avatarInitial => (_auth.currentEmail?.isNotEmpty ?? false)
      ? _auth.currentEmail!.substring(0, 1).toUpperCase()
      : '?';
}

/// Authentication state service.
///
/// A [ChangeNotifier] so Flutter widgets can rebuild on login/logout via
/// `AnimatedBuilder` — no external state-management package required.
///
/// Holds a [Lazy<UserProfileService>] instead of resolving it eagerly:
/// `UserProfileService` depends on `AuthService`, so an eager reference
/// would create a circular dependency. `Lazy` defers the lookup until
/// [profile] is actually accessed.
class AuthService extends ChangeNotifier implements Disposable {
  AuthService({
    required this.bridge,
    required this.logger,
    required Lazy<UserProfileService> profile,
  }) : _profile = profile;

  final ModularBridge bridge;
  final LoggingService logger;
  final Lazy<UserProfileService> _profile;

  String? _currentEmail;
  bool _isLoading = false;

  String? get currentEmail => _currentEmail;
  bool get isAuthenticated => _currentEmail != null;
  bool get isLoading => _isLoading;
  UserProfileService get profile => _profile.value;

  Future<void> login(String email, String password) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw ArgumentError('Email and password must not be empty.');
    }
    _isLoading = true;
    notifyListeners();
    try {
      logger.log('Authenticating $email...');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _currentEmail = email;
      bridge.publish(UserLoggedInEvent(userId: 'usr_789', email: email));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    final email = _currentEmail ?? 'unknown';
    logger.log('Logging out $email...');
    _currentEmail = null;
    bridge.publish(UserLoggedOutEvent(userId: 'usr_789'));
    notifyListeners();
  }

  @override
  void onDispose() => dispose();
}

/// Offline/mock implementation used by the "Use Mock" toggle.
///
/// Swapped in with a single `bridge.override<AuthService>(...)` call — the
/// same 1-line test override pattern `get_it` users know.
class MockAuthService extends AuthService {
  // ignore: use_super_parameters
  MockAuthService({
    required ModularBridge bridge,
    required LoggingService logger,
  }) : super(
          bridge: bridge,
          logger: logger,
          profile: bridge.lazy<UserProfileService>(),
        );

  @override
  Future<void> login(String email, String password) async {
    _currentEmailForMock = '[MOCK] $email';
    bridge.publish(
      UserLoggedInEvent(userId: 'mock_user', email: _currentEmailForMock!),
    );
    notifyListeners();
  }

  String? _currentEmailForMock;

  @override
  String? get currentEmail => _currentEmailForMock;

  @override
  bool get isAuthenticated => _currentEmailForMock != null;

  @override
  Future<void> logout() async {
    _currentEmailForMock = null;
    bridge.publish(UserLoggedOutEvent(userId: 'mock_user'));
    notifyListeners();
  }
}
