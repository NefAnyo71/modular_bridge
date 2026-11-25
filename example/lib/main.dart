// ModularBridge Feature Showcase — pure Flutter, zero external
// state-management dependencies.
//
// Every reactive surface in this app is driven by either:
//   • ChangeNotifier services resolved from the DI container
//     (AuthService, CartService, HomeController, EventLogService), or
//   • plain StatefulWidget setState for ephemeral UI state.
//
// Showcased ModularBridge features: type-safe config from assets,
// environment hot-switching, registerConfigBinding, parallel module
// registration, warmup hooks, health checks, Lazy<T> circular-dependency
// breaking, async singletons with BridgeRetryPolicy, module.subscribe
// options, scope stack with per-scope config overrides, 1-line overrides,
// callAsync, event interceptors (veto), resolution interceptors,
// metrics, diagnosticsReport, dependencyEventHistory and enableDevTools.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:modular_bridge/modular_bridge.dart';

import 'analytics/analytics_module.dart';
import 'auth/auth_module.dart';
import 'auth/auth_service.dart';
import 'cart/cart_module.dart';
import 'cart/cart_service.dart';
import 'core/core_module.dart';
import 'home/home_controller.dart';
import 'home/home_module.dart';

/// Builds a fresh list of all feature modules.
///
/// `parallel: true` initializes independent modules concurrently while the
/// topological sort still guarantees `dependencies` order.
List<FeatureModule> buildFeatureModules() => [
      CoreModule(),
      AnalyticsModule(),
      AuthModule(),
      HomeModule(),
      CartModule(),
    ];

/// Shared flag for the event-console "veto ping events" interceptor demo.
final ValueNotifier<bool> vetoPingEvents = ValueNotifier<bool>(false);

/// Last resolution timing reported by the timing interceptor.
final ValueNotifier<String> lastResolutionTiming = ValueNotifier<String>('—');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Type-safe config from a bundled JSON asset.
  final config = await BridgeConfig.fromAsset(
    'assets/config.json',
    loader: rootBundle.loadString,
    environment: BridgeEnvironment.dev,
  );
  ModularBridge.I.setConfig(config);

  // 2. Feature modules — parallel registration + warmup hooks.
  await ModularBridge.I.registerModules(buildFeatureModules(), parallel: true);
  await ModularBridge.I.warmup();

  // 3. DevTools VM service extensions (ext.modular_bridge.*).
  ModularBridge.I.enableDevTools();

  // 4. Resolution interceptor: structured timing for every get/getAsync.
  ModularBridge.I.addResolutionInterceptor(
    BridgeInterceptors.timing((t) {
      lastResolutionTiming.value =
          '${t.request.type} ${t.elapsed.inMicroseconds}µs';
    }),
  );

  // 5. Event interceptor: observe-only pass-through that can veto ping
  //    events when the console toggle is on (fan-out/veto demo).
  ModularBridge.I.eventBus.addEventInterceptor((event, next) {
    if (vetoPingEvents.value && event is _PingEvent) return; // veto
    next(event);
  });

  runApp(const ModularBridgeExampleApp());
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
  int _tab = 0;

  // Bumped after module load/unload or mock toggle so tabs re-resolve
  // services through tryGet (module unload disposes old instances).
  int _servicesVersion = 0;

  void _servicesChanged() => setState(() => _servicesVersion++);

  @override
  Widget build(BuildContext context) {
    final bridge = ModularBridge.I;
    final environment = bridge.config.environment;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.hub_outlined, color: Colors.indigo),
            SizedBox(width: 8),
            Text('ModularBridge',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        elevation: 1,
        actions: [
          _EnvBadge(environment: environment),
          IconButton(
            tooltip: 'Reset container & re-register modules',
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              final bridge = ModularBridge.I;
              await bridge.reset();
              await bridge.registerModules(buildFeatureModules());
              await bridge.warmup();
              _servicesChanged();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bridge reset & warmed up')),
                );
              }
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([vetoPingEvents, lastResolutionTiming]),
        builder: (context, _) => IndexedStack(
          index: _tab,
          children: [
            _FlowTab(
                key: ValueKey('flow$_servicesVersion'),
                onServicesChanged: _servicesChanged),
            _EventConsoleTab(key: ValueKey('events$_servicesVersion')),
            _InspectorTab(
                key: ValueKey('inspector$_servicesVersion'),
                onServicesChanged: _servicesChanged),
            const _ConfigStudioTab(key: ValueKey('config')),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Flow',
          ),
          NavigationDestination(
            icon: Icon(Icons.terminal_outlined),
            selectedIcon: Icon(Icons.terminal),
            label: 'Events',
          ),
          NavigationDestination(
            icon: Icon(Icons.layers_outlined),
            selectedIcon: Icon(Icons.layers),
            label: 'Inspector',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Config',
          ),
        ],
      ),
    );
  }
}

class _EnvBadge extends StatelessWidget {
  const _EnvBadge({required this.environment});
  final BridgeEnvironment environment;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (environment) {
      BridgeEnvironment.prod => (
          Colors.red.shade100,
          Colors.red.shade900,
          Icons.rocket_launch
        ),
      BridgeEnvironment.staging => (
          Colors.amber.shade100,
          Colors.amber.shade900,
          Icons.science
        ),
      _ => (Colors.green.shade100, Colors.green.shade900, Icons.developer_mode),
    };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withAlpha(120)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 4),
          Text(environment.name.toUpperCase(),
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 12, color: fg)),
        ],
      ),
    );
  }
}

/// Wraps a [ChangeNotifier] service resolved from the container; shows a
/// hint card when the owning module is currently unloaded.
class _ServiceBuilder extends StatelessWidget {
  const _ServiceBuilder({required this.service, required this.builder});

  final ChangeNotifier? service;
  final Widget Function(BuildContext context, ChangeNotifier service) builder;

  @override
  Widget build(BuildContext context) {
    final service = this.service;
    if (service == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: const [
              Icon(Icons.hourglass_empty, color: Colors.grey),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Module not loaded — open the Inspector tab and load it.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) => builder(context, service),
    );
  }
}

Widget _card(BuildContext context, {required Widget child}) => Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );

// =============================================================================
// TAB 1: APP FLOW � Auth (Lazy circular dep + override), Cart, Home, Async
// =============================================================================
class _FlowTab extends StatefulWidget {
  const _FlowTab({super.key, required this.onServicesChanged});
  final VoidCallback onServicesChanged;

  @override
  State<_FlowTab> createState() => _FlowTabState();
}

class _FlowTabState extends State<_FlowTab> {
  String _asyncInfo = '�';
  String _pingResult = '�';

  ModularBridge get bridge => ModularBridge.I;

  Future<void> _resolveSessionStore() async {
    // callAsync: async counterpart of the call syntax.
    final store = await bridge.callAsync<SessionStore>();
    setState(() =>
        _asyncInfo = '${store.endpoint} � connected=${store.isConnected}');
  }

  Future<void> _pingApi() async {
    final client = await bridge.callAsync<ApiClient>();
    final result = await client.get('/ping');
    setState(() => _pingResult = result);
  }

  void _toggleMock(bool useMock) {
    final bridge = ModularBridge.I;
    if (useMock) {
      bridge.override<AuthService>(MockAuthService(
        bridge: bridge,
        logger: bridge.get<LoggingService>(),
      ));
    } else {
      bridge.override<AuthService>(createAuthService(bridge));
    }
    widget.onServicesChanged();
  }

  @override
  Widget build(BuildContext context) {
    final auth = bridge.tryGet<AuthService>();
    final cart = bridge.tryGet<CartService>();
    final home = bridge.tryGet<HomeController>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoBanner(
          text:
              'Pure Flutter showcase: AuthService holds a Lazy<UserProfileService> '
              'to break a circular dependency. Cart/Home react to auth events '
              'with zero imports between modules.',
        ),
        const SizedBox(height: 16),

        // ---- Auth ------------------------------------------------------
        _card(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(children: [
                    Icon(Icons.security, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text('AuthModule (Lazy + Override)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                  Row(children: [
                    const Text('Mock', style: TextStyle(fontSize: 12)),
                    Switch(
                      value: auth is MockAuthService,
                      onChanged: _toggleMock,
                    ),
                  ]),
                ],
              ),
              Text(
                auth == null
                    ? 'AuthModule unloaded'
                    : auth.isAuthenticated
                        ? '? ${auth.currentEmail} � profile: ${auth.profile.displayName}'
                        : '? Signed out',
                style: TextStyle(
                  fontSize: 12,
                  color: auth?.isAuthenticated == true
                      ? Colors.green.shade700
                      : Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Divider(height: 20),
              _ServiceBuilder(
                service: auth,
                builder: (context, service) {
                  final authService = service as AuthService;
                  return Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.login),
                        label: Text(authService.isAuthenticated
                            ? 'Logged in'
                            : 'Login (dev@modular.dev)'),
                        onPressed: authService.isAuthenticated ||
                                authService.isLoading
                            ? null
                            : () =>
                                authService.login('dev@modular.dev', 'pass123'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
                      onPressed: authService.isAuthenticated
                          ? () => authService.logout()
                          : null,
                    ),
                  ]);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---- Cart ------------------------------------------------------
        _card(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ServiceBuilder(
                service: cart,
                builder: (context, service) {
                  final cartService = service as CartService;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            const Icon(Icons.shopping_cart_outlined,
                                color: Colors.teal),
                            const SizedBox(width: 8),
                            Text('CartModule (${cartService.itemCount})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                          ]),
                          Text('\$${cartService.totalPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'CartService is a ChangeNotifier resolved from DI � '
                        'AnimatedBuilder rebuilds this card. Logout clears '
                        'the cart via UserLoggedOutEvent.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const Divider(height: 20),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (name, price) in [
                            ('Flutter Hoodie', 49.0),
                            ('Dart Mug', 15.0),
                            ('Dev Laptop', 1299.0),
                          ])
                            ActionChip(
                              avatar: const Icon(Icons.add, size: 16),
                              label: Text('$name (\$$price)'),
                              onPressed: () => cartService.addItem(name, price),
                            ),
                          if (cartService.itemCount > 0)
                            ActionChip(
                              avatar: const Icon(Icons.clear_all,
                                  size: 16, color: Colors.red),
                              label: const Text('Clear'),
                              onPressed: () => cartService.clear(),
                            ),
                        ],
                      ),
                      if (cartService.items.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        for (final item in cartService.items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('� ${item.name}',
                                    style: const TextStyle(fontSize: 13)),
                                Text('\$${item.price.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---- Home ------------------------------------------------------
        _card(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ServiceBuilder(
                service: home,
                builder: (context, service) {
                  final homeController = service as HomeController;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        Icon(Icons.feed_outlined, color: Colors.deepPurple),
                        SizedBox(width: 8),
                        Text('HomeModule (Event-driven feed)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                      ]),
                      const SizedBox(height: 6),
                      const Text(
                        'HomeController subscribes to login/logout events '
                        'inside module.init � decoupled from AuthModule.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const Divider(height: 20),
                      if (homeController.isLoading)
                        const Center(
                            child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ))
                      else if (homeController.feedItems.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              'No feed items.\nLog in to trigger UserLoggedInEvent.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        for (final item in homeController.feedItems)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.check_circle_outline,
                                color: Colors.teal, size: 20),
                            title: Text(item,
                                style: const TextStyle(fontSize: 13)),
                          ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---- Async / callAsync -----------------------------------------
        _card(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.sync, color: Colors.blueGrey),
                SizedBox(width: 8),
                Text('Async lifecycles & callAsync',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
              const SizedBox(height: 8),
              const Text(
                'SessionStore is an eager asyncSingleton with a '
                'BridgeRetryPolicy � resolved during warmup(). ApiClient is '
                'config-bound: switching environment rebuilds it '
                'automatically.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Divider(height: 20),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.storage, size: 18),
                  label: const Text('Resolve SessionStore'),
                  onPressed: _resolveSessionStore,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.network_ping, size: 18),
                  label: const Text('Ping API (callAsync)'),
                  onPressed: _pingApi,
                ),
              ]),
              const SizedBox(height: 8),
              Text('session: $_asyncInfo',
                  style: const TextStyle(fontSize: 12)),
              Text('ping: $_pingResult', style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// TAB 2: EVENT CONSOLE � live bus feed, veto interceptor, once(), publishCounts
// =============================================================================
class _EventConsoleTab extends StatelessWidget {
  const _EventConsoleTab({super.key});

  @override
  Widget build(BuildContext context) {
    final bridge = ModularBridge.I;
    final logService = bridge.tryGet<EventLogService>();

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
                  'Event Bus (${bridge.eventBus.totalPublished} published)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: vetoPingEvents,
                builder: (context, veto, _) => FilterChip(
                  label:
                      const Text('Veto pings', style: TextStyle(fontSize: 12)),
                  selected: veto,
                  onSelected: (v) => vetoPingEvents.value = v,
                ),
              ),
              const SizedBox(width: 4),
              ElevatedButton.icon(
                icon: const Icon(Icons.send, size: 14),
                label: const Text('Fire Event', style: TextStyle(fontSize: 12)),
                onPressed: () =>
                    bridge.publish(_PingEvent('Ping from console')),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _ServiceBuilder(
            service: logService,
            builder: (context, service) {
              final logs = (service as EventLogService).history;
              return logs.isEmpty
                  ? const Center(
                      child: Text(
                        'No events yet.\nLogin, add cart items or fire a ping.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: logs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = logs[index];
                        final t = entry.timestamp;
                        final time = '${t.hour.toString().padLeft(2, '0')}:'
                            '${t.minute.toString().padLeft(2, '0')}:'
                            '${t.second.toString().padLeft(2, '0')}';
                        return ListTile(
                          dense: true,
                          leading: const CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.indigo,
                            child:
                                Icon(Icons.bolt, size: 16, color: Colors.white),
                          ),
                          title: Row(children: [
                            Expanded(
                              child: Text(entry.eventName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                      fontSize: 13)),
                            ),
                            Text(time,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          ]),
                          subtitle: Text(entry.summary,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black87)),
                        );
                      },
                    );
            },
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// TAB 3: INSPECTOR � modules lifecycle, metrics, health, scopes, diagnostics
// =============================================================================
class _InspectorTab extends StatefulWidget {
  const _InspectorTab({super.key, required this.onServicesChanged});
  final VoidCallback onServicesChanged;

  @override
  State<_InspectorTab> createState() => _InspectorTabState();
}

class _InspectorTabState extends State<_InspectorTab> {
  String _scopeNote = 'No request scope active';
  String _depEvents = '�';

  ModularBridge get bridge => ModularBridge.I;

  static const _moduleDefs = [
    ('CoreModule', 'Infrastructure, ApiClient, SessionStore'),
    ('AnalyticsModule', 'Event bus listener & live console'),
    ('AuthModule', 'Auth + Lazy-broken profile cycle'),
    ('HomeModule', 'Event-driven feed'),
    ('CartModule', 'Shopping cart with auto-clear'),
  ];

  FeatureModule _moduleFor(String name) => switch (name) {
        'CoreModule' => CoreModule(),
        'AnalyticsModule' => AnalyticsModule(),
        'AuthModule' => AuthModule(),
        'HomeModule' => HomeModule(),
        _ => CartModule(),
      };

  Future<void> _toggleModule(String name) async {
    final bridge = ModularBridge.I;
    try {
      if (bridge.activeModuleNames.contains(name)) {
        await bridge.unregisterModuleByName(name);
      } else {
        await bridge.registerModule(_moduleFor(name));
      }
    } on BridgeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    widget.onServicesChanged();
  }

  Future<void> _pushRequestScope() async {
    final bridge = ModularBridge.I;
    await bridge.pushNewScopeAsync(
      scopeName: 'request',
      init: (b) {
        // Registrations inside init route to the pushed scope implicitly.
        b.registerSingleton<UserContext>(
          UserContext(userId: 'u_42', tenantId: 'acme'),
        );
        b.currentScope!
            .setConfigValue('tenant', 'acme'); // scoped config override
      },
    );
    setState(() => _scopeNote =
        'tenant=${bridge.configValue<String>('tenant', defaultValue: '�')} '
            '� scopes=${bridge.activeScopeNames}');
  }

  Future<void> _popScope() async {
    await ModularBridge.I.popScope();
    setState(() => _scopeNote = 'scopes=${ModularBridge.I.activeScopeNames}');
  }

  Future<void> _showHealthCheck() async {
    final results = await bridge.checkModuleHealth();
    if (!mounted) return;
    final healthy = results.where((r) => r.isHealthy).length;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Health: $healthy/${results.length} healthy'),
        content: results.isEmpty
            ? const Text('No modules registered.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final r in results)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        r.isHealthy
                            ? Icons.check_circle_outline
                            : Icons.cancel_outlined,
                        color: r.isHealthy ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      title: Text(r.moduleName,
                          style: const TextStyle(fontSize: 14)),
                      subtitle: Text(
                        [
                          if (r.duration != null)
                            '${r.duration!.inMilliseconds}ms',
                          if (r.error != null) '$r.error',
                        ].join(' � '),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _showDiagnostics() async {
    final report = bridge.diagnosticsReport();
    if (!mounted) return;
    final payload = {
      'isHealthy': report.isHealthy,
      'registrations': report.registrations.length,
      'modules': report.moduleNames,
      'activeScopeNames': report.activeScopeNames,
      'scopeStack': report.scopeStack,
      'activeSubscriptionCount': report.activeSubscriptionCount,
      'pendingAsyncResolutions': report.pendingAsyncResolutions,
      'issues': report.issues,
      'metrics': report.metrics,
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('diagnosticsReport()'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(payload),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _showDepEvents() async {
    // dependencyEventHistory: replay last N registration events, then live.
    final events =
        await bridge.dependencyEventHistory(count: 8).take(8).toList();
    if (!mounted) return;
    setState(() => _depEvents = events
        .map((e) => '${e.kind.name} ${e.info.key.type}'
            '${e.scopeName != null ? ' @${e.scopeName}' : ''}')
        .join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ModularBridge.I;
    final metrics = bridge.metrics;
    final hitRatio = (metrics.cacheHitRatio * 100).toStringAsFixed(1);
    final activeModules = bridge.activeModuleNames.toSet();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoBanner(
          text: 'Dynamic module lifecycle: unload disposes dependencies '
              'and module-owned event subscriptions automatically.',
        ),
        const SizedBox(height: 16),

        // Metrics + timing
        _card(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(children: [
                    Icon(Icons.monitor_heart_outlined, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text('Bridge Diagnostics',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                  Wrap(spacing: 4, children: [
                    TextButton.icon(
                      icon: const Icon(Icons.favorite, size: 16),
                      label: const Text('Health'),
                      onPressed: _showHealthCheck,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.bug_report_outlined, size: 16),
                      label: const Text('Report'),
                      onPressed: _showDiagnostics,
                    ),
                  ]),
                ],
              ),
              const Divider(height: 20),
              Wrap(spacing: 16, runSpacing: 8, children: [
                _MetricChip(
                    label: 'Resolutions', value: '${metrics.totalResolutions}'),
                _MetricChip(
                    label: 'Cache Hits', value: '${metrics.totalCacheHits}'),
                _MetricChip(
                    label: 'Failures', value: '${metrics.totalFailures}'),
                _MetricChip(label: 'Hit Ratio', value: '$hitRatio%'),
              ]),
              const SizedBox(height: 8),
              ValueListenableBuilder<String>(
                valueListenable: lastResolutionTiming,
                builder: (context, timing, _) => Text(
                  'last timed resolution: $timing',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Modules
        ..._moduleDefs.map((def) {
          final (name, description) = def;
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
                onPressed: () => _toggleModule(name),
                child: Text(isRegistered ? 'Unload' : 'Load'),
              ),
            ),
          );
        }),
        const SizedBox(height: 16),

        // Scope stack demo
        _card(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.account_tree_outlined, color: Colors.teal),
                SizedBox(width: 8),
                Text('Scope stack demo',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
              const SizedBox(height: 6),
              const Text(
                'pushNewScopeAsync registers UserContext inside a '
                '"request" scope and sets a scoped config override � '
                'bridge.configValue resolves it through the scope chain.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Divider(height: 20),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.push_pin, size: 18),
                  label: const Text('Push request scope'),
                  onPressed: _pushRequestScope,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.call_made, size: 18),
                  label: const Text('Pop scope'),
                  onPressed: bridge.currentScope == null ? null : _popScope,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('DI event history'),
                  onPressed: _showDepEvents,
                ),
              ]),
              const SizedBox(height: 8),
              Text(_scopeNote, style: const TextStyle(fontSize: 12)),
              if (_depEvents != '�')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_depEvents,
                      style: const TextStyle(
                          fontSize: 11, fontFamily: 'monospace')),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// TAB 4: CONFIG STUDIO � env hot-switch, config binding, runtime overrides
// =============================================================================
class _ConfigStudioTab extends StatefulWidget {
  const _ConfigStudioTab({super.key});

  @override
  State<_ConfigStudioTab> createState() => _ConfigStudioTabState();
}

class _ConfigStudioTabState extends State<_ConfigStudioTab> {
  StreamSubscription<void>? _configSub;
  String _apiClientInfo = '�';

  ModularBridge get bridge => ModularBridge.I;

  @override
  void initState() {
    super.initState();
    // Reactive config: rebuild this tab on set/remove/env-switch.
    _configSub = bridge.config.onChanged.listen((_) => setState(() {}));
    _refreshApiInfo();
  }

  @override
  void dispose() {
    _configSub?.cancel();
    super.dispose();
  }

  void _refreshApiInfo() {
    final client = bridge.tryGet<ApiClient>();
    _apiClientInfo = client == null
        ? 'ApiClient not resolved'
        : '${client.baseUrl} � ${client.timeout.inSeconds}s';
  }

  void _switchEnvironment(BridgeEnvironment env) {
    bridge.config.switchEnvironment(env);
    // registerConfigBinding already reset ApiClient � just re-resolve.
    setState(_refreshApiInfo);
  }

  void _addRuntimeOverride() {
    bridge.config.set('runtime.flag', 'enabled-${DateTime.now().second}');
  }

  void _removeAllOverrides() {
    bridge.config.removeRuntimeOverrides();
  }

  @override
  Widget build(BuildContext context) {
    final config = bridge.config;
    final environment = config.environment;
    _refreshApiInfo();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Runtime flavor hot-switching',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              const Text(
                'switchEnvironment fires config.onChanged; the '
                'registerConfigBinding<ApiClient> resets and re-decodes '
                'automatically � no manual unregister needed.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              SegmentedButton<BridgeEnvironment>(
                segments: const [
                  ButtonSegment(
                      value: BridgeEnvironment.dev,
                      label: Text('DEV'),
                      icon: Icon(Icons.developer_mode)),
                  ButtonSegment(
                      value: BridgeEnvironment.staging,
                      label: Text('STAGING'),
                      icon: Icon(Icons.science)),
                  ButtonSegment(
                      value: BridgeEnvironment.prod,
                      label: Text('PROD'),
                      icon: Icon(Icons.rocket_launch)),
                ],
                selected: {environment},
                onSelectionChanged: (s) => _switchEnvironment(s.first),
              ),
              const SizedBox(height: 12),
              Text('bound ApiClient � $_apiClientInfo',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _card(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text('Active config values',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  Wrap(spacing: 4, children: [
                    TextButton.icon(
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: const Text('set()'),
                      onPressed: _addRuntimeOverride,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.cleaning_services_outlined,
                          size: 16),
                      label: const Text('removeRuntimeOverrides()'),
                      onPressed: _removeAllOverrides,
                    ),
                  ]),
                ],
              ),
              const Divider(height: 20),
              for (final entry in config.currentValues.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.key, style: const TextStyle(fontSize: 13)),
                      Flexible(
                        child: Text(
                          entry.value.toString(),
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Shared widgets & demo types
// =============================================================================
class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade200),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline, color: Colors.indigo),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: const TextStyle(fontSize: 13, color: Colors.indigo)),
        ),
      ]),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

/// Ping event used by the event-console "Fire Event" button � also the
/// target of the veto interceptor demo.
final class _PingEvent extends BridgeEvent {
  _PingEvent(this.message);
  final String message;

  @override
  String toString() => '_PingEvent("$message")';
}

/// Request-scoped context registered inside the pushed "request" scope.
class UserContext {
  const UserContext({required this.userId, required this.tenantId});
  final String userId;
  final String tenantId;

  @override
  String toString() => 'UserContext($userId @ $tenantId)';
}
