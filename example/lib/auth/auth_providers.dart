import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:modular_bridge/modular_bridge.dart';
import '../core/core_providers.dart';
import 'auth_events.dart';
import 'auth_module.dart';
import 'auth_repository.dart';

/// Immutable model representing the authentication state.
class AuthState {
  const AuthState({required this.isAuthenticated, this.email});
  final bool isAuthenticated;
  final String? email;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthState &&
          other.isAuthenticated == isAuthenticated &&
          other.email == email;

  @override
  int get hashCode => Object.hash(isAuthenticated, email);
}

/// Riverpod Notifier driving authentication state and listening to [BridgeEvent]s.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final bridge = ref.watch(bridgeProvider);
    final repo = bridge.tryGet<AuthRepository>();

    final loginSub = bridge.on<UserLoggedInEvent>().listen((event) {
      state = AuthState(isAuthenticated: true, email: event.email);
    });

    final logoutSub = bridge.on<UserLoggedOutEvent>().listen((_) {
      state = const AuthState(isAuthenticated: false, email: null);
    });

    ref.onDispose(() {
      loginSub.cancel();
      logoutSub.cancel();
    });

    return AuthState(
      isAuthenticated: repo?.isAuthenticated ?? false,
      email: repo?.currentEmail,
    );
  }

  Future<void> login(String email, String password) async {
    final bridge = ref.read(bridgeProvider);
    final repo = bridge.tryGet<AuthRepository>();
    if (repo != null) {
      await repo.login(email, password);
    }
  }

  Future<void> logout() async {
    final bridge = ref.read(bridgeProvider);
    final repo = bridge.tryGet<AuthRepository>();
    if (repo != null) {
      await repo.logout();
    }
  }
}

/// Provider exposing [AuthState].
final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

/// Notifier driving the 1-line Mock Override toggle demonstration.
class MockOverrideNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle(bool useMock) {
    final bridge = ref.read(bridgeProvider);
    if (useMock) {
      // 1-line mock override
      bridge.override<AuthRepository>(MockAuthRepository(bridge: bridge));
    } else {
      bridge.override<AuthRepository>(createAuthRepository(bridge));
    }
    state = useMock;
    ref.invalidate(authProvider);
  }
}

/// Provider exposing the active mock override state.
final mockOverrideProvider =
    NotifierProvider<MockOverrideNotifier, bool>(MockOverrideNotifier.new);
