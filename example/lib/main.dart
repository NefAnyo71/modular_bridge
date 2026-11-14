// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:modular_bridge/modular_bridge.dart';

import 'analytics/analytics_module.dart';
import 'analytics/analytics_providers.dart';
import 'auth/auth_module.dart';
import 'auth/auth_providers.dart';
import 'cart/cart_module.dart';
import 'cart/cart_providers.dart';
import 'core/core_module.dart';
import 'core/core_providers.dart';
import 'home/home_module.dart';
import 'home/home_providers.dart';

/// Riverpod StateProvider tracking the active bottom navigation tab index.
final selectedTabProvider = StateProvider<int>((ref) => 0);

/// Builds a fresh list of all feature modules in dependency-safe order.
List<FeatureModule> buildFeatureModules() => [
      CoreModule(),
      AnalyticsModule(),
      AuthModule(),
      HomeModule(),
      CartModule(),
    ];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Type-Safe Configuration for multiple flavors/environments
  final config = BridgeConfig(
    environment: BridgeEnvironment.dev,
    commonValues: {
      'appName': 'ModularBridge Riverpod Showcase',
      'version': '0.2.0',
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
  await ModularBridge.I.registerModules(buildFeatureModules());

  runApp(
    const ProviderScope(
      child: ModularBridgeProvider(
        child: ModularBridgeExampleApp(),
      ),
    ),
  );
}

class ModularBridgeExampleApp extends StatelessWidget {
  const ModularBridgeExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ModularBridge Riverpod Showcase',
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

/// Main showcase screen built completely as a Riverpod [ConsumerWidget].
///
/// Notice: ZERO [setState] calls. All reactive state flows cleanly through Riverpod Notifiers.
class ShowcaseScreen extends ConsumerWidget {
  const ShowcaseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final environment = ref.watch(environmentProvider);
    final selectedTab = ref.watch(selectedTabProvider);
    final bridge = ref.watch(bridgeProvider);

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
          // Active flavor badge
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: environment.isProd
                  ? Colors.red.shade100
                  : (environment.isStaging
                      ? Colors.amber.shade100
                      : Colors.green.shade100),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: environment.isProd
                    ? Colors.red.shade400
                    : (environment.isStaging
                        ? Colors.amber.shade700
                        : Colors.green.shade600),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  environment.isProd
                      ? Icons.rocket_launch
                      : (environment.isStaging
                          ? Icons.science
                          : Icons.developer_mode),
                  size: 16,
                  color: environment.isProd
                      ? Colors.red.shade900
                      : (environment.isStaging
                          ? Colors.amber.shade900
                          : Colors.green.shade900),
                ),
                const SizedBox(width: 4),
                Text(
                  environment.name.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: environment.isProd
                        ? Colors.red.shade900
                        : (environment.isStaging
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
              try {
                await bridge.reset();
                await bridge.registerModules(buildFeatureModules());
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Reset failed: $e')),
                  );
                }
                return;
              }
              ref.invalidate(environmentProvider);
              ref.invalidate(modulesProvider);
              ref.invalidate(authProvider);
              ref.invalidate(cartProvider);
              ref.invalidate(homeFeedProvider);
              ref.invalidate(eventLogsProvider);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'ModularBridge container reset & Riverpod refreshed!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: selectedTab,
        children: const [
          _AppFlowTab(),
          _EventConsoleTab(),
          _ModuleInspectorTab(),
          _ConfigStudioTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) {
          ref.read(selectedTabProvider.notifier).state = index;
        },
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
}

// =============================================================================
// TAB 1: INTERACTIVE APP FLOW (Auth, Cart, Home via Riverpod)
// =============================================================================
class _AppFlowTab extends ConsumerWidget {
  const _AppFlowTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final isMockActive = ref.watch(mockOverrideProvider);
    final cartItems = ref.watch(cartProvider);
    final cartCount = ref.watch(cartCountProvider);
    final cartTotal = ref.watch(cartTotalProvider);
    final homeFeed = ref.watch(homeFeedProvider);

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
                  '100% Riverpod State Management: CartModule & HomeModule react to '
                  'UserLoggedOutEvent without importing AuthModule!',
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
            side:
                BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('Use Mock:', style: TextStyle(fontSize: 12)),
                        Switch(
                          value: isMockActive,
                          onChanged: (useMock) {
                            ref
                                .read(mockOverrideProvider.notifier)
                                .toggle(useMock);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                Text(
                  isMockActive
                      ? '● Active: MockAuthRepository (1-line test override via Riverpod)'
                      : '● Active: AuthRepositoryImpl (Real dependency)',
                  style: TextStyle(
                    fontSize: 12,
                    color: isMockActive
                        ? Colors.deepOrange
                        : Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.login),
                        label: Text(
                          authState.isAuthenticated
                              ? 'Logged In: ${authState.email}'
                              : 'Login (developer@flutter.io)',
                        ),
                        onPressed: authState.isAuthenticated
                            ? null
                            : () async {
                                await ref
                                    .read(authProvider.notifier)
                                    .login('developer@flutter.io', 'pass123');
                              },
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
                      onPressed: !authState.isAuthenticated
                          ? null
                          : () async {
                              await ref.read(authProvider.notifier).logout();
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
            side:
                BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
                        const Icon(Icons.shopping_cart_outlined,
                            color: Colors.teal),
                        const SizedBox(width: 8),
                        Text(
                          'CartModule ($cartCount items)',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    if (cartCount > 0)
                      Text(
                        'Total: \$${cartTotal.toStringAsFixed(2)}',
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
                  'CartNotifier listens to UserLoggedOutEvent via BridgeEventBus. '
                  'Logging out clears this cart automatically!',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Divider(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: const Text('Flutter Hoodie (\$49)'),
                      onPressed: () {
                        ref
                            .read(cartProvider.notifier)
                            .addItem('Flutter Hoodie', 49.0);
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: const Text('Dart Mug (\$15)'),
                      onPressed: () {
                        ref
                            .read(cartProvider.notifier)
                            .addItem('Dart Mug', 15.0);
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: const Text('Dev Laptop (\$1,299)'),
                      onPressed: () {
                        ref
                            .read(cartProvider.notifier)
                            .addItem('Dev Laptop', 1299.0);
                      },
                    ),
                    if (cartCount > 0)
                      ActionChip(
                        avatar: const Icon(Icons.clear_all,
                            size: 16, color: Colors.red),
                        label: const Text('Clear Cart'),
                        onPressed: () {
                          ref.read(cartProvider.notifier).clear();
                        },
                      ),
                  ],
                ),
                if (cartItems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...cartItems.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('• ${item.name}',
                              style: const TextStyle(fontSize: 13)),
                          Text(
                            '\$${item.price.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
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
            side:
                BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
                      'HomeModule (Riverpod Stream Feed)',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Feed is managed by HomeFeedNotifier which listens to UserLoggedInEvent / UserLoggedOutEvent.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Divider(height: 20),
                if (homeFeed.isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (homeFeed.items.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    alignment: Alignment.center,
                    child: const Text(
                      'No feed items.\nLog in to trigger UserLoggedInEvent across the bridge.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ...homeFeed.items.map(
                    (item) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle_outline,
                          color: Colors.teal, size: 20),
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
}

// =============================================================================
// TAB 2: LIVE EVENT CONSOLE (Real-time Event Stream via Riverpod)
// =============================================================================
class _EventConsoleTab extends ConsumerWidget {
  const _EventConsoleTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventLogs = ref.watch(eventLogsProvider);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              const Icon(Icons.terminal, size: 20, color: Colors.black87),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Event Bus Stream (${eventLogs.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.send, size: 14),
                label: const Text('Fire Event', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  ref.read(bridgeProvider).publish(
                        _SamplePingEvent('Manual ping from Event Console'),
                      );
                },
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Clear history',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () {
                  ref.read(eventLogsProvider.notifier).clear();
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: eventLogs.isEmpty
              ? const Center(
                  child: Text(
                    'No events recorded yet.\nPerform actions on the Modules tab or click "Fire Event".',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: eventLogs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = eventLogs[index];
                    final timeString =
                        '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
                        '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
                        '${entry.timestamp.second.toString().padLeft(2, '0')}';

                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.indigo.shade50,
                        child: const Icon(Icons.bolt,
                            size: 16, color: Colors.indigo),
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
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        entry.summary,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black87),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// =============================================================================
// TAB 3: MODULE & MEMORY INSPECTOR (Auto-Dispose & Dynamic Unloading)
// =============================================================================
class _ModuleInspectorTab extends ConsumerWidget {
  const _ModuleInspectorTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeModules = ref.watch(modulesProvider);

    final moduleDefinitions = [
      (
        'CoreModule',
        'Infrastructure, ApiClient, LoggingService',
        () => CoreModule()
      ),
      (
        'AnalyticsModule',
        'Event bus listener & live console recorder',
        () => AnalyticsModule()
      ),
      (
        'AuthModule',
        'Authentication state and login/logout events',
        () => AuthModule()
      ),
      ('HomeModule', 'Decoupled consumer of user events', () => HomeModule()),
      (
        'CartModule',
        'Decoupled shopping cart with auto-clear',
        () => CartModule()
      ),
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
                  'When you unregister a module, ModularBridge instantly disposes all of its '
                  'registered dependencies and EventBus listeners to eliminate memory leaks.',
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
                color:
                    isRegistered ? Colors.green.shade300 : Colors.grey.shade300,
              ),
            ),
            child: ListTile(
              leading: Icon(
                isRegistered ? Icons.check_circle : Icons.pause_circle_outline,
                color: isRegistered ? Colors.green : Colors.grey,
              ),
              title: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(description, style: const TextStyle(fontSize: 12)),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isRegistered ? Colors.red.shade50 : Colors.green.shade50,
                  foregroundColor:
                      isRegistered ? Colors.red : Colors.green.shade800,
                  elevation: 0,
                ),
                onPressed: () async {
                  try {
                    if (isRegistered) {
                      await ref
                          .read(modulesProvider.notifier)
                          .unloadModule(name);
                    } else {
                      await ref
                          .read(modulesProvider.notifier)
                          .loadModule(factory());
                    }
                  } on BridgeException catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.message)),
                      );
                    }
                    return;
                  }
                  ref.invalidate(authProvider);
                  ref.invalidate(cartProvider);
                  ref.invalidate(homeFeedProvider);
                },
                child: Text(isRegistered ? 'Unload Module' : 'Load Module'),
              ),
            ),
          );
        }),
      ],
    );
  }
}

// =============================================================================
// TAB 4: FLAVOR & CONFIG STUDIO (Runtime Hot-Switch via Riverpod)
// =============================================================================
class _ConfigStudioTab extends ConsumerWidget {
  const _ConfigStudioTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final environment = ref.watch(environmentProvider);
    final config = ref.watch(bridgeProvider).config;
    // Rebuild whenever any config value changes (set/remove/environment switch).
    ref.watch(configChangesProvider);

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.primaryContainer.withAlpha(60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side:
                BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
                  'Driven through Riverpod EnvironmentNotifier: changing flavor updates '
                  'all config consumers without restarting the app.',
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
                  selected: {environment},
                  onSelectionChanged: (newSelection) {
                    ref
                        .read(environmentProvider.notifier)
                        .switchEnvironment(newSelection.first);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side:
                BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    IconButton(
                      tooltip: 'Add Custom Key at Runtime',
                      icon: const Icon(Icons.add_circle_outline,
                          color: Colors.indigo),
                      onPressed: () => _showAddKeyDialog(context, ref),
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
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black87),
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

  void _showAddKeyDialog(BuildContext context, WidgetRef ref) {
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
              decoration: const InputDecoration(
                  labelText: 'Config Key (e.g. promoCode)'),
            ),
            TextField(
              controller: valueController,
              decoration:
                  const InputDecoration(labelText: 'Value (e.g. SUMMER2026)'),
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
                ref.read(bridgeProvider).config.set(
                    keyController.text.trim(), valueController.text.trim());
                Navigator.pop(ctx);
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
