import 'package:material_ui/material_ui.dart';
import 'package:modular_bridge/modular_bridge.dart';

// -----------------------------------------------------------------------------
// 1. DOMAIN EVENTS
// -----------------------------------------------------------------------------
final class UserLoggedInEvent extends BridgeEvent {
  UserLoggedInEvent({required this.userId, required this.email});
  final String userId;
  final String email;
}

final class UserLoggedOutEvent extends BridgeEvent {
  UserLoggedOutEvent({required this.userId, required this.reason});
  final String userId;
  final String reason;
}

// -----------------------------------------------------------------------------
// 2. SERVICES & MODULES
// -----------------------------------------------------------------------------
class ApiClient {
  ApiClient({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 30),
  });

  final String baseUrl;
  final Duration timeout;

  Future<bool> ping() async => true;
}

abstract class AuthRepository {
  bool get isLoggedIn;
  String? get email;
  Future<void> login(String email);
  Future<void> logout();
}

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required ApiClient apiClient,
    required ModularBridge bridge,
  })  : _apiClient = apiClient,
        _bridge = bridge;

  final ApiClient _apiClient;
  final ModularBridge _bridge;

  bool _isLoggedIn = false;
  String? _email;

  @override
  bool get isLoggedIn => _isLoggedIn;

  @override
  String? get email => _email;

  @override
  Future<void> login(String email) async {
    assert(_apiClient.baseUrl.isNotEmpty);
    _isLoggedIn = true;
    _email = email;
    _bridge.publish(UserLoggedInEvent(userId: 'usr_123', email: email));
  }

  @override
  Future<void> logout() async {
    _isLoggedIn = false;
    _email = null;
    _bridge.publish(
      UserLoggedOutEvent(
        userId: 'usr_123',
        reason: 'User logged out manually',
      ),
    );
  }
}

final class CoreModule extends FeatureModule {
  @override
  String get name => 'CoreModule';

  @override
  void registerDependencies(ModularBridge bridge) {
    bridge.registerLazySingleton<ApiClient>(
      () => ApiClient(
        baseUrl: bridge.config.getString('apiBaseUrl'),
        timeout: bridge.config.getDuration('apiTimeout'),
      ),
    );
  }
}

final class AuthModule extends FeatureModule {
  @override
  String get name => 'AuthModule';

  @override
  List<Type> get dependencies => [CoreModule];

  @override
  void registerDependencies(ModularBridge bridge) {
    bridge.registerLazySingleton<AuthRepository>(
      () => AuthRepositoryImpl(
        apiClient: bridge.get<ApiClient>(),
        bridge: bridge,
      ),
    );
  }
}

class HomeController extends ChangeNotifier {
  String message = 'Please log in.';

  void onUserLoggedIn(String email) {
    message = 'Welcome back, $email! Personalized feed loaded.';
    notifyListeners();
  }

  void onUserLoggedOut(String reason) {
    message = 'User logged out ($reason). Feed cleared.';
    notifyListeners();
  }
}

final class HomeModule extends FeatureModule {
  @override
  String get name => 'HomeModule';

  @override
  List<Type> get dependencies => [CoreModule];

  @override
  void registerDependencies(ModularBridge bridge) {
    bridge.registerLazySingleton<HomeController>(() => HomeController());
  }

  @override
  void init(ModularBridge bridge) {
    final controller = bridge.get<HomeController>();

    // Listen to Auth events in a completely decoupled fashion:
    subscribe<UserLoggedInEvent>(
      bridge,
      (e) => controller.onUserLoggedIn(e.email),
    );
    subscribe<UserLoggedOutEvent>(
      bridge,
      (e) => controller.onUserLoggedOut(e.reason),
    );
  }
}

// -----------------------------------------------------------------------------
// 3. APPLICATION INITIALIZATION
// -----------------------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize type-safe configuration
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

  // 2. Register feature modules
  await ModularBridge.I.registerModules([
    CoreModule(),
    AuthModule(),
    HomeModule(),
  ]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bridge = ModularBridge.I;
    final authRepo = bridge.get<AuthRepository>();
    final homeController = bridge.get<HomeController>();
    final config = bridge.config;
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<BridgeEnvironment>(
      stream: config.onEnvironmentChanged,
      initialData: config.environment,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            title: const Text('Modular Bridge Demo'),
            actions: [
              // Flavor Hot-Switch Button
              TextButton.icon(
                onPressed: () {
                  final nextEnv = config.environment.isDev
                      ? BridgeEnvironment.prod
                      : BridgeEnvironment.dev;
                  config.switchEnvironment(nextEnv);
                },
                icon: Icon(Icons.swap_horiz, color: colorScheme.onPrimary),
                label: Text(
                  config.environment.name.toUpperCase(),
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Active API Base URL: ${config.getString('apiBaseUrl')}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ListenableBuilder(
                    listenable: homeController,
                    builder: (context, _) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          homeController.message,
                          style: TextStyle(
                            fontSize: 16,
                            color: colorScheme.onPrimaryContainer,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.login),
                        label: const Text('Log In'),
                        onPressed: () => authRepo.login('developer@flutter.io'),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.logout),
                        label: const Text('Log Out'),
                        onPressed: () => authRepo.logout(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
