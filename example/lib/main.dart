import 'package:flutter/material.dart';
import 'package:modular_bridge/modular_bridge.dart';

import 'auth/auth_module.dart';
import 'auth/auth_repository.dart';
import 'core/core_module.dart';
import 'home/home_controller.dart';
import 'home/home_module.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Type-Safe Configuration for multiple flavors/environments
  final config = BridgeConfig(
    environment: BridgeEnvironment.dev,
    commonValues: {
      'appName': 'ModularBridge Showcase',
      'version': '1.0.0',
    },
    environmentValues: {
      BridgeEnvironment.dev: {
        'apiBaseUrl': 'https://dev.api.modularbridge.io',
        'apiTimeout': const Duration(seconds: 15),
        'enableBiometrics': false,
        'retryCount': 3,
      },
      BridgeEnvironment.staging: {
        'apiBaseUrl': 'https://staging.api.modularbridge.io',
        'apiTimeout': const Duration(seconds: 10),
        'enableBiometrics': true,
        'retryCount': 2,
      },
      BridgeEnvironment.prod: {
        'apiBaseUrl': 'https://api.modularbridge.io',
        'apiTimeout': const Duration(seconds: 5),
        'enableBiometrics': true,
        'retryCount': 1,
      },
    },
  );

  ModularBridge.I.setConfig(config);

  // 2. Register feature modules in decoupled order
  await ModularBridge.I.registerModules([
    CoreModule(),
    AuthModule(),
    HomeModule(),
  ]);

  runApp(
    const ModularBridgeProvider(
      child: ModularBridgeExampleApp(),
    ),
  );
}

class ModularBridgeExampleApp extends StatelessWidget {
  const ModularBridgeExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Modular Bridge Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      home: const ShowcaseScreen(),
    );
  }
}

class ShowcaseScreen extends StatefulWidget {
  const ShowcaseScreen({super.key});

  @override
  State<ShowcaseScreen> createState() => _ShowcaseScreenState();
}

class _ShowcaseScreenState extends State<ShowcaseScreen> {
  bool _isMockActive = false;

  @override
  Widget build(BuildContext context) {
    final bridge = context.bridge;
    final config = context.config;
    final authRepo = bridge.get<AuthRepository>();
    final homeController = bridge.get<HomeController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ModularBridge Architecture'),
        elevation: 2,
        actions: [
          IconButton(
            tooltip: 'Reset Bridge',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await bridge.reset();
              await bridge.registerModules([CoreModule(), AuthModule(), HomeModule()]);
              if (context.mounted) {
                setState(() {});
              }
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: homeController,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // -------------------------------------------------------------
              // 1. ENVIRONMENT / FLAVOR HOT-SWITCH SECTION
              // -------------------------------------------------------------
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.primaryContainer.withAlpha(80),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Active Flavor / Environment',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Chip(
                            label: Text(
                              config.environment.name.toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: config.environment.isProd
                                ? Colors.red.shade100
                                : Colors.green.shade100,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Hot-switch runtime configuration without restarting the application:',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<BridgeEnvironment>(
                        segments: const [
                          ButtonSegment(
                            value: BridgeEnvironment.dev,
                            label: Text('DEV'),
                            icon: Icon(Icons.developer_mode),
                          ),
                          ButtonSegment(
                            value: BridgeEnvironment.staging,
                            label: Text('STAGING'),
                            icon: Icon(Icons.science),
                          ),
                          ButtonSegment(
                            value: BridgeEnvironment.prod,
                            label: Text('PROD'),
                            icon: Icon(Icons.rocket_launch),
                          ),
                        ],
                        selected: {config.environment},
                        onSelectionChanged: (newSelection) {
                          config.switchEnvironment(newSelection.first);
                          // Re-register CoreModule to pick up new client configuration
                          bridge.unregister<ApiClient>();
                          bridge.registerLazySingleton<ApiClient>(() {
                            return ApiClient(
                              baseUrl: bridge.config.getString('apiBaseUrl'),
                              timeout: bridge.config.getDuration('apiTimeout'),
                            );
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // -------------------------------------------------------------
              // 2. TYPE-SAFE CONFIGURATION INSPECTION
              // -------------------------------------------------------------
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Type-Safe Config Injections',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Divider(height: 20),
                      _buildConfigRow('API Base URL', config.getString('apiBaseUrl')),
                      _buildConfigRow(
                        'Request Timeout',
                        '${config.getDuration('apiTimeout').inSeconds} seconds',
                      ),
                      _buildConfigRow(
                        'Biometrics Feature Flag',
                        config.getBool('enableBiometrics').toString(),
                      ),
                      _buildConfigRow('Max Retries', config.getInt('retryCount').toString()),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // -------------------------------------------------------------
              // 3. AUTH MODULE & SINGLE-LINE MOCK OVERRIDE
              // -------------------------------------------------------------
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'AuthModule (DI & Events)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Switch(
                            value: _isMockActive,
                            onChanged: (useMock) {
                              setState(() {
                                _isMockActive = useMock;
                                if (useMock) {
                                  // Single-line Mock Override
                                  bridge.override<AuthRepository>(MockAuthRepository());
                                } else {
                                  bridge.override<AuthRepository>(
                                    AuthRepositoryImpl(
                                      apiClient: bridge.get<ApiClient>(),
                                      logger: bridge.get<LoggingService>(),
                                      bridge: bridge,
                                    ),
                                  );
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      Text(
                        _isMockActive
                            ? 'Active: MockAuthRepository (Unit Test Override)'
                            : 'Active: AuthRepositoryImpl (Real Dependency)',
                        style: TextStyle(
                          fontSize: 12,
                          color: _isMockActive ? Colors.deepOrange : Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.login),
                              label: const Text('Login User'),
                              onPressed: authRepo.isAuthenticated
                                  ? null
                                  : () async {
                                      await authRepo.login('developer@flutter.io', 'pass123');
                                      setState(() {});
                                    },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.logout),
                              label: const Text('Logout'),
                              onPressed: !authRepo.isAuthenticated
                                  ? null
                                  : () async {
                                      await authRepo.logout();
                                      setState(() {});
                                    },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // -------------------------------------------------------------
              // 4. DECOUPLED HOME MODULE (EVENT BUS CONSUMER)
              // -------------------------------------------------------------
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.dynamic_feed, color: Colors.indigo),
                          const SizedBox(width: 8),
                          const Text(
                            'HomeModule (Decoupled Event Listener)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Reacts automatically to UserLoggedInEvent / UserLoggedOutEvent '
                        'without importing any AuthModule internals.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                      const Divider(height: 20),
                      if (homeController.isLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (homeController.feedItems.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          alignment: Alignment.center,
                          child: const Text(
                            'No feed items loaded.\nClick "Login User" above to trigger UserLoggedInEvent.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        ...homeController.feedItems.map(
                          (item) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.check_circle_outline, color: Colors.teal),
                            title: Text(item),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConfigRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black87, fontSize: 13)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

