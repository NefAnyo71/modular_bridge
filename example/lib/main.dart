// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:modular_bridge/modular_bridge.dart';

import 'analytics/analytics_module.dart';
import 'auth/auth_module.dart';
import 'auth/auth_repository.dart';
import 'cart/cart_module.dart';
import 'cart/cart_service.dart';
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
    AnalyticsModule(),
    AuthModule(),
    HomeModule(),
    CartModule(),
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
      title: 'ModularBridge Showcase',
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
  int _currentTabIndex = 0;
  bool _isMockActive = false;

  @override
  Widget build(BuildContext context) {
    final bridge = context.bridge;
    final config = context.config;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.hub_outlined, color: Colors.indigo),
            SizedBox(width: 8),
            Text(
              'ModularBridge Architecture',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        elevation: 1,
        actions: [
          // Active flavor chip
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: config.environment.isProd
                  ? Colors.red.shade100
                  : (config.environment.isStaging
                      ? Colors.amber.shade100
                      : Colors.green.shade100),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: config.environment.isProd
                    ? Colors.red.shade400
                    : (config.environment.isStaging
                        ? Colors.amber.shade700
                        : Colors.green.shade600),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  config.environment.isProd
                      ? Icons.rocket_launch
                      : (config.environment.isStaging
                          ? Icons.science
                          : Icons.developer_mode),
                  size: 16,
                  color: config.environment.isProd
                      ? Colors.red.shade900
                      : (config.environment.isStaging
                          ? Colors.amber.shade900
                          : Colors.green.shade900),
                ),
                const SizedBox(width: 4),
                Text(
                  config.environment.name.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: config.environment.isProd
                        ? Colors.red.shade900
                        : (config.environment.isStaging
                            ? Colors.amber.shade900
                            : Colors.green.shade900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Reset and Reinitialize Bridge',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await bridge.reset();
              await bridge.registerModules([
                CoreModule(),
                AnalyticsModule(),
                AuthModule(),
                HomeModule(),
                CartModule(),
              ]);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('ModularBridge container reset & re-initialized!'),
                    duration: Duration(seconds: 2),
                  ),
                );
                setState(() {});
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _buildAppFlowTab(context),
          _buildEventConsoleTab(context),
          _buildModuleInspectorTab(context),
          _buildConfigStudioTab(context),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) => setState(() => _currentTabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Modules Flow',
          ),
          NavigationDestination(
            icon: Icon(Icons.terminal_outlined),
            selectedIcon: Icon(Icons.terminal),
            label: 'Event Console',
          ),
          NavigationDestination(
            icon: Icon(Icons.layers_outlined),
            selectedIcon: Icon(Icons.layers),
            label: 'Module Inspector',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Config Studio',
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: INTERACTIVE APP FLOW (Auth, Cart, Home)
  // ===========================================================================
  Widget _buildAppFlowTab(BuildContext context) {
    final bridge = context.bridge;
    final authRepo = bridge.tryGet<AuthRepository>();
    final homeController = bridge.tryGet<HomeController>();
    final cartService = bridge.tryGet<CartService>();

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // Information banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.indigo.shade200),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.indigo),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This tab demonstrates decoupled communication: CartModule and HomeModule '
                  'react to UserLoggedOutEvent without importing AuthModule!',
                  style: TextStyle(fontSize: 13, color: Colors.indigo),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 1. Auth Module Card
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
                    const Row(
                      children: [
                        Icon(Icons.security, color: Colors.indigo),
                        SizedBox(width: 8),
                        Text(
                          'AuthModule (DI & Events)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('Use Mock:', style: TextStyle(fontSize: 12)),
                        Switch(
                          value: _isMockActive,
                          onChanged: authRepo == null
                              ? null
                              : (useMock) {
                                  setState(() {
                                    _isMockActive = useMock;
                                    if (useMock) {
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
                  ],
                ),
                Text(
                  _isMockActive
                      ? '● Active: MockAuthRepository (1-line test override)'
                      : '● Active: AuthRepositoryImpl (Real dependency)',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isMockActive ? Colors.deepOrange : Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Divider(height: 24),
                if (authRepo == null)
                  const Text('AuthModule is currently unloaded.')
                else
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.login),
                          label: Text(
                            authRepo.isAuthenticated
                                ? 'Logged In as ${authRepo.currentEmail}'
                                : 'Login (developer@flutter.io)',
                          ),
                          onPressed: authRepo.isAuthenticated
                              ? null
                              : () async {
                                  await authRepo.login('developer@flutter.io', 'pass123');
                                  setState(() {});
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.logout),
                        label: const Text('Logout'),
                        onPressed: !authRepo.isAuthenticated
                            ? null
                            : () async {
                                await authRepo.logout();
                                setState(() {});
                              },
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 2. Shopping Cart Card
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
                    Row(
                      children: [
                        const Icon(Icons.shopping_cart_outlined, color: Colors.teal),
                        const SizedBox(width: 8),
                        Text(
                          'CartModule (${cartService?.itemCount ?? 0} items)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    if (cartService != null && cartService.itemCount > 0)
                      Text(
                        'Total: \$${cartService.totalPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                          fontSize: 15,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Listens to UserLoggedOutEvent with auto-dispose. If user logs out, cart clears instantly.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Divider(height: 20),
                if (cartService == null)
                  const Text('CartModule is currently unloaded.')
                else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: const Text('Flutter Hoodie (\$49)'),
                        onPressed: () => cartService.addItem('Flutter Hoodie', 49.0),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: const Text('Dart Mug (\$15)'),
                        onPressed: () => cartService.addItem('Dart Mug', 15.0),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: const Text('Dev Laptop (\$1,299)'),
                        onPressed: () => cartService.addItem('Dev Laptop', 1299.0),
                      ),
                      if (cartService.itemCount > 0)
                        ActionChip(
                          avatar: const Icon(Icons.clear_all, size: 16, color: Colors.red),
                          label: const Text('Clear Cart'),
                          onPressed: () => cartService.clear(),
                        ),
                    ],
                  ),
                  if (cartService.items.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...cartService.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('• ${item.name}', style: const TextStyle(fontSize: 13)),
                            Text('\$${item.price.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 3. Home Feed Card
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
                const Row(
                  children: [
                    Icon(Icons.feed_outlined, color: Colors.deepPurple),
                    SizedBox(width: 8),
                    Text(
                      'HomeModule (Personalized Feed)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Populated when UserLoggedInEvent arrives; automatically emptied on UserLoggedOutEvent.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Divider(height: 20),
                if (homeController == null)
                  const Text('HomeModule is currently unloaded.')
                else if (homeController.isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (homeController.feedItems.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    alignment: Alignment.center,
                    child: const Text(
                      'No feed items.\nLog in to broadcast UserLoggedInEvent.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ...homeController.feedItems.map(
                    (item) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle_outline, color: Colors.teal, size: 20),
                      title: Text(item, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 2: LIVE EVENT CONSOLE (Real-time Event Stream)
  // ===========================================================================
  Widget _buildEventConsoleTab(BuildContext context) {
    final logService = context.bridge.tryGet<EventLogService>();

    return Column(
      children: [
        // Console Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              const Icon(Icons.terminal, size: 20, color: Colors.black87),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Event Bus Stream (${logService?.history.length ?? 0})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.send, size: 14),
                label: const Text('Fire Event', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  context.bridge.publish(
                    _SamplePingEvent('Manual ping from Event Console'),
                  );
                },
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Clear history',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: logService == null ? null : () => logService.clear(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Console Log Stream List
        Expanded(
          child: logService == null || logService.history.isEmpty
              ? const Center(
                  child: Text(
                    'No events recorded yet.\nPerform actions on the Modules tab or click "Fire Custom Event".',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListenableBuilder(
                  listenable: logService,
                  builder: (context, _) {
                    return ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: logService.history.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = logService.history[index];
                        final timeString =
                            '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
                            '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
                            '${entry.timestamp.second.toString().padLeft(2, '0')}';

                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.indigo.shade50,
                            child: const Icon(Icons.bolt, size: 16, color: Colors.indigo),
                          ),
                          title: Row(
                            children: [
                              Text(
                                entry.eventName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                timeString,
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            entry.summary,
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 3: MODULE & MEMORY INSPECTOR (Auto-Dispose & Dynamic Unloading)
  // ===========================================================================
  Widget _buildModuleInspectorTab(BuildContext context) {
    final bridge = context.bridge;
    final activeModules = bridge.activeModuleNames;

    final moduleDefinitions = [
      ('CoreModule', 'Infrastructure, ApiClient, LoggingService', () => CoreModule()),
      ('AnalyticsModule', 'Event bus listener & live console recorder', () => AnalyticsModule()),
      ('AuthModule', 'Authentication state and login/logout events', () => AuthModule()),
      ('HomeModule', 'Decoupled consumer of user events', () => HomeModule()),
      ('CartModule', 'Decoupled shopping cart with auto-clear', () => CartModule()),
    ];

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: const Row(
            children: [
              Icon(Icons.memory, color: Colors.brown),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Dynamic Module Lifecycle & Auto-Disposal:\n'
                  'When you unregister a module, ModularBridge instantly removes all of its '
                  'registered singletons, factories, and EventBus subscriptions, preventing memory leaks.',
                  style: TextStyle(fontSize: 12, color: Colors.brown),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...moduleDefinitions.map((def) {
          final (name, description, factory) = def;
          final isRegistered = activeModules.contains(name);

          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isRegistered ? Colors.green.shade300 : Colors.grey.shade300,
              ),
            ),
            child: ListTile(
              leading: Icon(
                isRegistered ? Icons.check_circle : Icons.pause_circle_outline,
                color: isRegistered ? Colors.green : Colors.grey,
              ),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(description, style: const TextStyle(fontSize: 12)),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRegistered ? Colors.red.shade50 : Colors.green.shade50,
                  foregroundColor: isRegistered ? Colors.red : Colors.green.shade800,
                  elevation: 0,
                ),
                onPressed: () async {
                  if (isRegistered) {
                    await bridge.unregisterModuleByName(name);
                  } else {
                    await bridge.registerModule(factory());
                  }
                  setState(() {});
                },
                child: Text(isRegistered ? 'Unload Module' : 'Load Module'),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ===========================================================================
  // TAB 4: FLAVOR & CONFIG STUDIO (Runtime Hot-Switch)
  // ===========================================================================
  Widget _buildConfigStudioTab(BuildContext context) {
    final bridge = context.bridge;
    final config = context.config;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // Environment switcher card
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.primaryContainer.withAlpha(60),
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
                  'Runtime Flavor Hot-Switching',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Switching environments re-evaluates the config store and immediately '
                  'notifies all dependent widgets without restarting the app.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 16),
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
                    // Reconfigure ApiClient for the new flavor
                    bridge.unregister<ApiClient>();
                    bridge.registerLazySingleton<ApiClient>(() {
                      return ApiClient(
                        baseUrl: bridge.config.getString('apiBaseUrl'),
                        timeout: bridge.config.getDuration('apiTimeout'),
                      );
                    });
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Active Configurations Inspection Table
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
                      'Type-Safe Config Parameters',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    IconButton(
                      tooltip: 'Add Custom Key at Runtime',
                      icon: const Icon(Icons.add_circle_outline, color: Colors.indigo),
                      onPressed: () => _showAddKeyDialog(context),
                    ),
                  ],
                ),
                const Divider(height: 20),
                ...config.currentValues.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          entry.key,
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                        Text(
                          entry.value.toString(),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showAddKeyDialog(BuildContext context) {
    final keyController = TextEditingController();
    final valueController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add / Override Config Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              decoration: const InputDecoration(labelText: 'Config Key (e.g. promoCode)'),
            ),
            TextField(
              controller: valueController,
              decoration: const InputDecoration(labelText: 'Value (e.g. SUMMER2026)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (keyController.text.isNotEmpty) {
                context.config.set(keyController.text.trim(), valueController.text.trim());
                Navigator.pop(ctx);
                setState(() {});
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Sample custom ping event for live console testing.
final class _SamplePingEvent extends BridgeEvent {
  _SamplePingEvent(this.message);
  final String message;

  @override
  String toString() => '_SamplePingEvent("$message")';
}
