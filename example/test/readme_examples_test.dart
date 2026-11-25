import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modular_bridge/modular_bridge.dart';
import 'package:modular_bridge_example/mini_app.dart' as mini;

class MockAuthRepository implements mini.AuthRepository {
  bool _isLoggedIn = false;
  String? _email;

  @override
  bool get isLoggedIn => _isLoggedIn;

  @override
  String? get email => _email;

  @override
  Future<void> login(String email) async {
    _isLoggedIn = true;
    _email = email;
  }

  @override
  Future<void> logout() async {
    _isLoggedIn = false;
    _email = null;
  }
}

class UserProfileCard extends StatelessWidget {
  const UserProfileCard({super.key});

  @override
  Widget build(BuildContext context) {
    final bridge = ModularBridge.I;
    final authRepo = bridge.get<mini.AuthRepository>();

    return StreamBuilder<BridgeEnvironment>(
      stream: bridge.config.onEnvironmentChanged,
      initialData: bridge.config.environment,
      builder: (context, _) {
        return Card(
          child: ListTile(
            title: Text('User: ${authRepo.email ?? 'Guest'}'),
            subtitle: Text('Environment: ${bridge.config.environment.name}'),
            trailing: IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => authRepo.logout(),
            ),
          ),
        );
      },
    );
  }
}

class _CartService {
  final List<String> items = ['hoodie'];
  void clearCart() => items.clear();
}

final class _CartModule extends FeatureModule {
  @override
  String get name => 'CartModule';

  @override
  void registerDependencies(ModularBridge bridge) {
    bridge.registerLazySingleton<_CartService>(() => _CartService());
  }

  @override
  void init(ModularBridge bridge) {
    final cartService = bridge.get<_CartService>();
    subscribe<mini.UserLoggedOutEvent>(bridge, (event) {
      cartService.clearCart();
    });
  }
}

class _RequestContext {
  _RequestContext({required this.userId});
  final String userId;
}

void main() {
  tearDown(() async {
    await ModularBridge.I.reset();
    ModularBridge.resetInstance();
  });

  test('Single-line mock override unit test', () async {
    final bridge = ModularBridge.createIsolated();

    bridge.registerLazySingleton<mini.AuthRepository>(
      () => mini.AuthRepositoryImpl(
        apiClient: mini.ApiClient(baseUrl: 'https://dev.api.example.com'),
        bridge: bridge,
      ),
    );

    final mock = MockAuthRepository();
    bridge.override<mini.AuthRepository>(mock);

    final resolved = bridge.get<mini.AuthRepository>();
    expect(resolved, isA<MockAuthRepository>());

    await resolved.login('dev@example.com');
    expect(resolved.isLoggedIn, isTrue);
    expect(resolved.email, 'dev@example.com');

    await resolved.logout();
    expect(resolved.isLoggedIn, isFalse);
    expect(resolved.email, isNull);

    await bridge.dispose();
  });

  test('UserLoggedOutEvent clears CartService via decoupled bus', () async {
    final bridge = ModularBridge.createIsolated();
    bridge.setConfig(
      BridgeConfig(
        environment: BridgeEnvironment.dev,
        environmentValues: {
          BridgeEnvironment.dev: {
            'apiBaseUrl': 'https://dev.api.example.com',
            'apiTimeout': const Duration(seconds: 30),
          },
        },
      ),
    );

    await bridge.registerModules([
      mini.CoreModule(),
      mini.AuthModule(),
      _CartModule(),
    ]);

    final cart = bridge.get<_CartService>();
    expect(cart.items, isNotEmpty);

    await bridge.get<mini.AuthRepository>().logout();
    expect(cart.items, isEmpty);

    await bridge.dispose();
  });

  test('Scoped RequestContext compiles and disposes cleanly', () async {
    final bridge = ModularBridge.createIsolated();
    const userId = 'u_42';

    final scope = bridge.createScope(scopeName: 'checkout');
    scope.registerSingleton<_RequestContext>(_RequestContext(userId: userId));
    expect(scope.get<_RequestContext>().userId, userId);

    await scope.dispose();
    await bridge.dispose();
  });

  testWidgets('Full End-to-End mini_app renders with visible M3 AppBar button',
      (tester) async {
    final config = BridgeConfig(
      environment: BridgeEnvironment.dev,
      environmentValues: {
        BridgeEnvironment.dev: {
          'apiBaseUrl': 'https://dev.api.example.com',
          'apiTimeout': const Duration(seconds: 30),
        },
        BridgeEnvironment.prod: {
          'apiBaseUrl': 'https://api.example.com',
          'apiTimeout': const Duration(seconds: 10),
        },
      },
    );
    ModularBridge.I.setConfig(config);
    await ModularBridge.I.registerModules([
      mini.CoreModule(),
      mini.AuthModule(),
      mini.HomeModule(),
    ]);

    await tester.pumpWidget(const mini.MyApp());
    await tester.pump();

    expect(find.text('Modular Bridge Demo'), findsOneWidget);
    expect(find.text('DEV'), findsOneWidget);
    expect(
      find.text('Active API Base URL: https://dev.api.example.com'),
      findsOneWidget,
    );

    // Verify Material 3 AppBar contrast: button text is not invisible white-on-light.
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final devText = tester.widget<Text>(find.text('DEV'));
    expect(appBar.backgroundColor, isNotNull);
    expect(devText.style?.color, isNot(equals(appBar.backgroundColor)));

    // Hot-switch flavor via AppBar button
    await tester.tap(find.text('DEV'));
    await tester.pump();
    expect(find.text('PROD'), findsOneWidget);
    expect(
      find.text('Active API Base URL: https://api.example.com'),
      findsOneWidget,
    );

    // Login & Logout flow
    await tester.tap(find.text('Log In'));
    await tester.pump();
    expect(
      find.text('Welcome back, developer@flutter.io! Personalized feed loaded.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Log Out'));
    await tester.pump();
    expect(
      find.text('User logged out (User logged out manually). Feed cleared.'),
      findsOneWidget,
    );
  });

  testWidgets('UserProfileCard displays AuthRepository.email', (tester) async {
    final bridge = ModularBridge.I;
    final mock = MockAuthRepository();
    await mock.login('profile@flutter.io');
    bridge.override<mini.AuthRepository>(mock);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UserProfileCard())),
    );
    await tester.pump();

    expect(find.text('User: profile@flutter.io'), findsOneWidget);
  });
}
