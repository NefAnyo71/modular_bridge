// Generates `modular-bridge.code-snippets` for VS Code by scanning the
// public API of package:modular_bridge and combining it with hand-curated
// templates for the most common workflows.
//
// Usage:
//   dart run generate_snippets.dart [--out <path>]
//
// Copy the generated file into your project's `.vscode/` directory (or your
// user snippets folder) to activate the `mb.*` snippets.

import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// Curated templates — the polished, copy-paste-ready snippets.
// ---------------------------------------------------------------------------

/// A snippet definition: prefix -> (description, body lines).
typedef SnippetDef = ({String description, List<String> body});

const Map<String, SnippetDef> curated = {
  'mb.module': (
    description: 'FeatureModule — full module skeleton',
    body: [
      'final class \${1:FeatureName}Module extends FeatureModule {',
      '  @override',
      '  String get name => \'\${1:feature}\';',
      '',
      '  @override',
      '  List<Type> get dependencies => const [\${2:CoreModule}];',
      '',
      '  @override',
      '  List<BridgeEnvironment>? get environments => null;',
      '',
      '  @override',
      '  FutureOr<void> registerDependencies(ModularBridge bridge) async {',
      '    \${3}',
      '  }',
      '',
      '  @override',
      '  FutureOr<void> init(ModularBridge bridge) {',
      '    \${4}',
      '  }',
      '',
      '  @override',
      '  FutureOr<bool> healthCheck(ModularBridge bridge) async {',
      '    return true;',
      '  }',
      '}',
    ],
  ),
  'mb.module.registerdeps': (
    description: 'Module.registerDependencies — lazy singleton registration',
    body: [
      'bridge.registerLazySingleton<\${1:Repository}>(',
      '  () => \${1:Repository}Impl(\${2:bridge.get<Dependency>()}),',
      '  onDispose: (repo) => repo.dispose(),',
      ');',
    ],
  ),
  'mb.module.subscribe': (
    description:
        'Module.subscribe — event subscription bound to module lifetime',
    body: [
      'subscribe<\${1:MyEvent}>(bridge, (event) {',
      '  \${2}',
      '});',
    ],
  ),
  'mb.module.dispose': (
    description: 'FeatureModule.dispose — teardown hook',
    body: [
      '@override',
      '@mustCallSuper()',
      'FutureOr<void> dispose(ModularBridge bridge) async {',
      '  \${1}',
      '  await super.dispose(bridge);',
      '}',
    ],
  ),
  'mb.event': (
    description: 'BridgeEvent — immutable domain event',
    body: [
      'final class \${1:SomethingHappened}Event extends BridgeEvent {',
      '  const \${1:SomethingHappened}Event({required this.\${2:field}});',
      '',
      '  final \${3:String} \${2:field};',
      '}',
    ],
  ),
  'mb.event.publish': (
    description: 'Publish an event on the bridge event bus',
    body: [
      'bridge.eventBus.publish(\${1:MyEvent()}\${2});',
    ],
  ),
  'mb.event.subscribe': (
    description: 'Subscribe to an event (managed BridgeSubscription)',
    body: [
      'final sub = bridge.eventBus.subscribe<\${1:MyEvent}>(\${2:(event) {\n    \${3}\n  }}, ownerId: \'\${4:owner}\');',
    ],
  ),
  'mb.event.once': (
    description: 'Wait for the next event of type T',
    body: [
      'final event = await bridge.eventBus.once<\${1:MyEvent}>(timeout: const Duration(seconds: \${2:5}));',
    ],
  ),
  'mb.event.onlatest': (
    description: 'Stream that replays the latest event then continues live',
    body: [
      'bridge.eventBus.onLatest<\${1:MyEvent}>().listen((event) {',
      '  \${2}',
      '});',
    ],
  ),
  'mb.config': (
    description: 'BridgeConfig — environments + common values',
    body: [
      'final config = BridgeConfig(',
      '  environment: BridgeEnvironment.\${1|dev,staging,prod|},',
      '  commonValues: {',
      '    \'\${2:appName}\': \'\${3:MyApp}\',',
      '  },',
      '  environmentValues: {',
      '    BridgeEnvironment.dev: {',
      '      \'\${4:apiBaseUrl}\': \'http://localhost:8080\',',
      '    },',
      '    BridgeEnvironment.staging: {',
      '      \'\${4:apiBaseUrl}\': \'https://staging.example.com\',',
      '    },',
      '    BridgeEnvironment.prod: {',
      '      \'\${4:apiBaseUrl}\': \'https://api.example.com\',',
      '    },',
      '  },',
      ');',
      '',
      'ModularBridge.I.setConfig(config);',
    ],
  ),
  'mb.config.env': (
    description: 'BridgeConfig from a .env file (pure Dart loader)',
    body: [
      'final config = await BridgeConfig.fromEnvFile(',
      "  'assets/.env',",
      '  loader: (path) => File(path).readAsString(),',
      ');',
    ],
  ),
  'mb.config.json': (
    description: 'BridgeConfig from a JSON asset/string',
    body: [
      'final config = await BridgeConfig.fromAsset(',
      "  'assets/config.json',",
      '  loader: (path) => File(path).readAsString(),',
      ');',
    ],
  ),
  'mb.config.get': (
    description: 'Typed config read with default',
    body: [
      'final \${1:String} \${2:value} = config.get\${3|String,int,double,bool,Duration,Uri|}(\'\${4:key}\'\${5:, defaultValue: \${6}});',
    ],
  ),
  'mb.config.switch': (
    description: 'Hot-switch the active environment at runtime',
    body: [
      'config.switchEnvironment(BridgeEnvironment.\${1|dev,staging,prod|});',
    ],
  ),
  'mb.config.binding': (
    description: 'registerConfigBinding — dependency rebuilt on config change',
    body: [
      'bridge.registerConfigBinding<ApiConfig>(',
      "  configKey: '\${1:api}',",
      '  decoder: (value) => ApiConfig.fromMap(value as Map<String, dynamic>),',
      ');',
    ],
  ),
  'mb.register.module': (
    description: 'Register a single FeatureModule',
    body: [
      'await ModularBridge.I.registerModule(\${1:AuthModule()}\${2:, checkHealth: true});',
    ],
  ),
  'mb.register.modules': (
    description: 'Register a batch of modules (topologically sorted)',
    body: [
      'await ModularBridge.I.registerModules([',
      '  \${1:CoreModule()},',
      '  \${2:AuthModule()},',
      '  \${3:HomeModule()},',
      ']);',
    ],
  ),
  'mb.register.singleton': (
    description: 'registerSingleton — eager shared instance',
    body: [
      'bridge.registerSingleton<\${1:Service}>(\${1:Service}()\${2:, onDispose: (s) => s.dispose()});',
    ],
  ),
  'mb.register.lazy': (
    description: 'registerLazySingleton — created on first get<T>()',
    body: [
      'bridge.registerLazySingleton<\${1:Repository}>(',
      '  () => \${1:Repository}Impl(\${2:bridge.get<Dependency>()}),',
      '  instanceName: \'\${3}\',',
      '  dependsOn: [dep<\${4:Dependency}>()],',
      ');',
    ],
  ),
  'mb.register.factory': (
    description: 'registerFactory — new instance per resolution',
    body: [
      'bridge.registerFactory<\${1:Service}>(() => \${1:Service}());',
    ],
  ),
  'mb.register.async': (
    description: 'registerAsyncSingleton — async factory with retry policy',
    body: [
      'bridge.registerAsyncSingleton<\${1:ApiClient}>(',
      '  () => \${1:ApiClient}.connect(\${2:config.getString(\'apiBaseUrl\')}),',
      '  eager: \${3|true,false|},',
      '  retryPolicy: const BridgeRetryPolicy(',
      '    maxAttempts: \${4:3},',
      "    delay: Duration(milliseconds: \${5:200}),",
      '    backoff: \${6:2.0},',
      '  ),',
      ');',
    ],
  ),
  'mb.register.withdeps': (
    description: 'registerSingletonWithDependencies — ordered startup',
    body: [
      'bridge.registerSingletonWithDependencies<\${1:CheckoutService}>(',
      '  factoryFunc: (bridge) => \${1:CheckoutService}(',
      '    bridge.get<\${2:PaymentGateway}>(),',
      '  ),',
      '  dependsOn: [dep<\${2:PaymentGateway}>()],',
      ');',
    ],
  ),
  'mb.register.param': (
    description: 'registerFactoryParam + getParam pair',
    body: [
      'bridge.registerFactoryParam<\${1:Handler}, \${2:String}, \${3:int}>(',
      '  (\${2:param1}, \${3:param2}) => \${1:Handler}(\${2:param1}, \${3:param2}),',
      ');',
      '',
      'final handler = bridge.getParam<\${1:Handler}, \${2:String}, \${3:int}>(',
      '  param1: \'\${4}\',',
      '  param2: \${5:0},',
      ');',
    ],
  ),
  'mb.get': (
    description: 'Resolve a dependency synchronously',
    body: [
      'final \${1:Service} \${2:service} = bridge.get<\${1:Service}>\${3|, instanceName: \'name\'|}();',
    ],
  ),
  'mb.getasync': (
    description: 'Resolve a dependency asynchronously',
    body: [
      'final \${1:Service} \${2:service} = await bridge.getAsync<\${1:Service}>();',
    ],
  ),
  'mb.tryget': (
    description: 'Optional resolution — null when not registered',
    body: [
      'final \${1:Service}? \${2:service} = bridge.tryGet<\${1:Service}>();',
    ],
  ),
  'mb.getall': (
    description: 'Resolve every registration of type T (incl. named)',
    body: [
      'final all = bridge.getAll<\${1:Service}>();',
    ],
  ),
  'mb.override': (
    description: '1-line mock override for tests',
    body: [
      'bridge.override<\${1:Service}>(\${2:mockService}\${3:, instanceName: \'name\'});',
    ],
  ),
  'mb.isolated': (
    description: 'Create an isolated bridge for tests',
    body: [
      'final bridge = ModularBridge.createIsolated(',
      '  config: BridgeConfig(environment: BridgeEnvironment.dev),',
      ');',
    ],
  ),
  'mb.scope': (
    description: 'Request/session-scoped dependencies',
    body: [
      'final scope = await bridge.createScopeAsync((scope) async {',
      '  scope.registerLazySingleton<\${1:RequestContext}>(',
      "    () => RequestContext(\${2:requestId}),",
      '  );',
      '});',
      '',
      'try {',
      '  final ctx = scope.get<\${1:RequestContext}>();',
      '  \${3}',
      '} finally {',
      '  await scope.dispose();',
      '}',
    ],
  ),
  'mb.scope.push': (
    description: 'pushNewScope — stack-based scoping',
    body: [
      'bridge.pushNewScope(',
      "  scopeName: '\${1:request}',",
      '  init: (bridge) {',
      '    \${2}',
      '  },',
      '  isFinal: \${3|true,false|},',
      ');',
    ],
  ),
  'mb.allready': (
    description: 'Await all readiness-tracked dependencies',
    body: [
      'await bridge.allReady(timeout: const Duration(seconds: \${1:10}));',
    ],
  ),
  'mb.warmup': (
    description: 'Eagerly resolve all singleton-style registrations',
    body: [
      'await bridge.warmup();',
    ],
  ),
  'mb.modulesready': (
    description: 'onModulesReady — run code after all modules init',
    body: [
      'ModularBridge.I.onModulesReady((bridge) async {',
      '  \${1}',
      '});',
    ],
  ),
  'mb.healthcheck': (
    description: 'Run health checks on all registered modules',
    body: [
      'final results = await bridge.checkModuleHealth();',
      'for (final r in results.where((r) => !r.isHealthy)) {',
      '  reportBridgeError(r.error ?? StateError(\'unhealthy\'), StackTrace.current,',
      "    context: 'Module \${r.moduleName} unhealthy');",
      '}',
    ],
  ),
  'mb.unregistered': (
    description: 'Unregister a module / dependency',
    body: [
      'await bridge.unregisterModule<\${1:FeatureModule}>\${2|, force: true|}();',
    ],
  ),
  'mb.reset': (
    description: 'Reset the container (tests / logout flows)',
    body: [
      'await bridge.reset(disposeInstances: \${1|true,false|});',
    ],
  ),
  'mb.retry': (
    description: 'BridgeRetryPolicy for flaky async dependencies',
    body: [
      'const retryPolicy = BridgeRetryPolicy(',
      '  maxAttempts: \${1:3},',
      '  delay: Duration(milliseconds: \${2:250}),',
      '  backoff: \${3:2.0},',
      '  retryIf: (error) => error is! BridgeConfigKeyNotFoundException,',
      ');',
    ],
  ),
  'mb.interceptor': (
    description: 'Resolution interceptor — timing/logging around get<T>()',
    body: [
      'bridge.addResolutionInterceptor(',
      '  (request, next) {',
      '    final sw = Stopwatch()..start();',
      "    developer.log('Resolving \${request.type}', name: 'modular_bridge');",
      '    final result = next();',
      "    developer.log('Resolved in \${sw.elapsedMilliseconds}ms', name: 'modular_bridge');",
      '    return result;',
      '  },',
      ');',
    ],
  ),
};

/// Method names that already have a curated snippet — skip auto-generation
/// for these to avoid noisy duplicates.
final Set<String> curatedAnchors = {
  for (final key in curated.keys) key.split('.').last.toLowerCase(),
};

// ---------------------------------------------------------------------------
// Source scanning — discover public classes, methods and getters.
// ---------------------------------------------------------------------------

final _classRe = RegExp(
  r'^\s*(?:(?:abstract|final|sealed|base|interface|mixin)\s+)*'
  r'(class|enum|mixin)\s+([A-Za-z_]\w*)',
);
final _methodRe = RegExp(
  r'^\s*(?:(?:static|factory|external)\s+)*'
  r'([A-Za-z_][\w<>,?\.\[\] ]*?)\s+'
  r'([A-Za-z_][\w\.]*)\s*(<[^{\n(]*>)?\s*\(',
);
final _getterRe = RegExp(
  r'^\s*(?:static\s+)?[A-Za-z_][\w<>,?\.\[\] ]*?\s+'
  r'get\s+([A-Za-z_]\w*)\s*(?:=>|\{)',
);
final _topLevelFnRe = RegExp(
  r'^(?:Future|FutureOr|Stream|void|bool|int|double|String|Type|Object|dynamic|'
  r'DependencyKey|Map|List|Set|Iterable|Duration|Uri|Never|Null)'
  r'[\w<>,?\. ]*?\s+([A-Za-z_]\w*)\s*(<[^{\n(]*>)?\s*\(',
);

/// Files whose methods are internal machinery, not developer-facing API.
final Set<String> skippedFiles = {
  'dependency_descriptor.dart',
  'resolution_context.dart',
  'resolution_interceptor.dart',
  'dependency_event.dart',
  'annotations.dart',
  'feature_module.dart',
  'bridge_subscription.dart',
};

/// Return-type tokens that indicate an in-body call site (`await foo()`),
/// not a member declaration.
final Set<String> keywordTypes = {
  'await',
  'return',
  'throw',
  'yield',
  'assert',
  'new',
  'const',
  'super',
  'this',
  'var',
  'final',
  'if',
  'for',
  'while',
  'switch',
  'catch',
  'else',
  'do',
  'in',
  'is',
  'as',
  'case',
  'try',
  'late',
  'on',
};

/// Receiver prefixes allowed for dotted call names like `bridge.eventBus.x`.
final Set<String> allowedDotReceivers = {
  'bridge',
  'scope',
  'config',
  'eventBus',
  'bus',
  'ModularBridge',
  'BridgeConfig',
  'BridgeEventBus',
  'BridgeScope',
  'DependencyKey',
  'BridgeRetryPolicy',
  'FeatureModule',
};

/// Public classes that should not get an instantiation snippet.
final Set<String> skipClasses = {
  'BridgeScope', // internal constructor — use createScope/pushNewScope
};

/// Public method names on internal helper types that are noise as snippets.
/// Compared case-insensitively — keep entries lowercase.
final Set<String> denylistedMethods = {
  'resolve',
  'resolveasync',
  'resolveparam',
  'resolveparamasync',
  'readiness',
  'readconfig',
  'signalreadyfromroot',
  'getfromroot',
  'getasyncfromroot',
  'getparamfromroot',
  'getparamasyncfromroot',
  'resolvedependencykey',
  'resolvedependencykeyfromroot',
  'notifydependencyevent',
  'trackscope',
  'untrackscope',
  'notifyscopeconfigbindings',
  'finddescriptorbyinstancefromroot',
  'localdescriptors',
  'currentmoduleownerforscope',
  'tostring',
  'hashcode',
  'nosuchmethod',
  'runzoned',
  'function',
  'run',
  'visit',
  'warmable',
  'resetlazy',
  'init',
  'dependencies',
  'environments',
  'name',
  'i',
};

/// Receiver expression for `static` members, keyed by file name.
String? staticReceiverFor(String fileName) {
  if (fileName.contains('bridge_config')) return 'BridgeConfig';
  if (fileName.contains('bridge_environment')) return 'BridgeEnvironment';
  if (fileName.contains('modular_bridge_container')) return 'ModularBridge';
  if (fileName.contains('event_bus')) return 'BridgeEventBus';
  if (fileName.contains('bridge_scope')) return 'BridgeScope';
  return null;
}

/// Chooses the receiver expression for auto-generated call snippets based
/// on which source file declared the member.
String receiverFor(String fileName) {
  if (fileName.contains('bridge_environment')) return 'BridgeEnvironment.dev';
  if (fileName.contains('bridge_config')) return 'config';
  if (fileName.contains('env_file')) return '';
  if (fileName.contains('event_bus')) return 'bridge.eventBus';
  if (fileName.contains('dependency_graph')) return 'bridge.dependencyGraph()';
  if (fileName.contains('dependency_metrics')) return 'bridge.metrics';
  if (fileName.contains('bridge_scope')) return 'scope';
  if (fileName.contains('container') ||
      fileName.contains('modular_bridge_container')) {
    return 'bridge';
  }
  if (fileName.contains('bridge_error_reporter')) return '';
  return 'bridge';
}

/// Splits [text] on top-level commas, ignoring commas nested inside
/// parentheses, brackets, braces and strings.
List<String> splitTopLevel(String text) {
  final parts = <String>[];
  var depth = 0;
  var quote = '';
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quote.isNotEmpty) {
      if (ch == quote && text[i - 1] != r'\') quote = '';
      continue;
    }
    if (ch == "'" || ch == '"') {
      quote = ch;
    } else if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
    } else if (ch == ')' || ch == ']' || ch == '}') {
      depth--;
    } else if (ch == ',' && depth == 0) {
      parts.add(text.substring(start, i).trim());
      start = i + 1;
    }
  }
  final tail = text.substring(start).trim();
  if (tail.isNotEmpty) parts.add(tail);
  return parts;
}

/// Extracts the parameter name (and optional default) from one parameter
/// segment like `required String? instanceName` or `bool override = false`.
({String name, String? defaultValue}) parseParam(String segment) {
  var s = segment.trim();
  if (s.startsWith('required ')) s = s.substring('required '.length);
  // Strip a leading type — take the last identifier before '=' or end.
  final eq = s.indexOf('=');
  final head = eq >= 0 ? s.substring(0, eq).trim() : s;
  final def = eq >= 0 ? s.substring(eq + 1).trim() : null;
  final nameMatch = RegExp(r'([A-Za-z_]\w*)\s*$').firstMatch(head);
  final name = nameMatch?.group(1) ?? 'arg';
  return (name: name, defaultValue: def);
}

/// Builds the argument list for an auto-generated call snippet.
/// Returns a list of (placeholderIndex -> argument text) already numbered.
List<String> buildArgs(String signatureInner, int startIndex) {
  final args = <String>[];
  var index = startIndex;
  // Named parameters live inside the first top-level `{...}`.
  var braceStart = -1;
  var depth = 0;
  var quote = '';
  for (var i = 0; i < signatureInner.length; i++) {
    final ch = signatureInner[i];
    if (quote.isNotEmpty) {
      if (ch == quote && signatureInner[i - 1] != r'\') quote = '';
      continue;
    }
    if (ch == "'" || ch == '"') {
      quote = ch;
    } else if (ch == '(' || ch == '[') {
      depth++;
    } else if (ch == ')' || ch == ']') {
      depth--;
    } else if (ch == '{' && depth == 0) {
      braceStart = i;
      break;
    }
  }

  final positionalText = braceStart >= 0
      ? signatureInner.substring(0, braceStart)
      : signatureInner;
  final namedText = braceStart >= 0
      ? signatureInner.substring(
          braceStart + 1, signatureInner.lastIndexOf('}'))
      : '';

  for (final seg in splitTopLevel(positionalText)) {
    if (seg.isEmpty) continue;
    final p = parseParam(seg);
    args.add('\${$index:${p.name}}');
    index++;
  }
  if (namedText.isNotEmpty) {
    for (final seg in splitTopLevel(namedText)) {
      if (seg.isEmpty) continue;
      final p = parseParam(seg);
      final def = p.defaultValue;
      args.add(def != null
          ? '${p.name}: \${$index:$def}'
          : '${p.name}: \${$index:${p.name}}');
      index++;
    }
  }
  return args;
}

/// Finds the balanced `(...)` signature starting at [openParen] in [src].
String? extractSignature(String src, int openParen) {
  var depth = 0;
  var quote = '';
  for (var i = openParen; i < src.length; i++) {
    final ch = src[i];
    if (quote.isNotEmpty) {
      if (ch == quote && src[i - 1] != r'\') quote = '';
      continue;
    }
    if (ch == "'" || ch == '"') {
      quote = ch;
    } else if (ch == '(') {
      depth++;
    } else if (ch == ')') {
      depth--;
      if (depth == 0) {
        return src.substring(openParen + 1, i);
      }
    }
  }
  return null;
}

void main(List<String> args) {
  final scriptDir = File(Platform.script.toFilePath()).parent.path;
  final outIndex = args.indexOf('--out');
  final outPath = outIndex >= 0 && outIndex + 1 < args.length
      ? args[outIndex + 1]
      : '$scriptDir\\modular-bridge.code-snippets';

  final libDir = Directory('$scriptDir\\..\\lib');
  if (!libDir.existsSync()) {
    stderr.writeln('Could not find lib/ next to vscode_snippets/.');
    exitCode = 1;
    return;
  }

  final snippets = <String, Map<String, Object?>>{};
  final seenPrefixes = <String>{};

  void add(String prefix, String description, List<String> body,
      [String scope = 'dart']) {
    if (!seenPrefixes.add(prefix)) return;
    snippets[prefix] = {
      'prefix': prefix,
      'description': description,
      'scope': scope,
      'body': body,
    };
  }

  // 1. Curated templates first so they win prefix collisions.
  for (final entry in curated.entries) {
    add(entry.key, entry.value.description, entry.value.body);
  }

  // 2. Scan sources for public API to generate call-site snippets.
  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    // Process the container first so `bridge.*` wins prefix collisions
    // against BridgeScope's mirrored API (`scope.*`).
    ..sort((a, b) {
      final aFirst = a.uri.pathSegments.last.contains('container') ? 0 : 1;
      final bFirst = b.uri.pathSegments.last.contains('container') ? 0 : 1;
      return aFirst.compareTo(bFirst);
    });

  for (final file in dartFiles) {
    final fileName = file.uri.pathSegments.last;
    if (skippedFiles.contains(fileName)) continue;
    final src = file.readAsStringSync();
    final lines = src.split('\n');
    final receiver = receiverFor(fileName);
    final isTopLevel =
        fileName == 'env_file.dart' || fileName == 'bridge_error_reporter.dart';

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Classes / enums / mixins.
      final classMatch = _classRe.firstMatch(line);
      if (classMatch != null) {
        final kind = classMatch.group(1)!;
        final name = classMatch.group(2)!;
        if (name.startsWith('_')) continue;
        if (kind == 'enum' || kind == 'mixin') continue;
        final isAbstract = line.contains('abstract');
        final isSealed = line.contains('sealed');
        if (isAbstract || isSealed || skipClasses.contains(name)) continue;
        add(
          'mb.new.$name',
          'Instantiate $name',
          ['$name(\${1})'],
        );
        continue;
      }

      // Methods (skip inside skipped files already handled above).
      final methodMatch = _methodRe.firstMatch(line);
      if (methodMatch != null && !isTopLevel) {
        final retType = methodMatch.group(1)!.trim();
        final retFirstWord = retType.split(RegExp(r'\s+')).first;
        if (keywordTypes.contains(retFirstWord.toLowerCase())) continue;
        final rawName = methodMatch.group(2)!;
        final name = rawName.contains('.') ? rawName.split('.').last : rawName;
        final nameLower = name.toLowerCase();
        if (name.startsWith('_') ||
            name == 'Function' ||
            denylistedMethods.contains(nameLower) ||
            curatedAnchors.contains(nameLower)) {
          continue;
        }
        // Resolve the effective call receiver for dotted names.
        String? dottedReceiver;
        var effectiveReceiver = receiver;
        final isStaticMember = line.trimLeft().startsWith('static ');
        if (isStaticMember) {
          effectiveReceiver = staticReceiverFor(fileName) ?? '';
        }
        var effectiveName = rawName;
        if (rawName.contains('.')) {
          final parts = rawName.split('.');
          final head = parts.first;
          final isStaticish = head[0].toUpperCase() == head[0];
          if (isStaticish || allowedDotReceivers.contains(head)) {
            dottedReceiver = parts.sublist(0, parts.length - 1).join('.');
            effectiveName = parts.last;
          } else {
            continue; // local variable call — not declarative API
          }
        }
        // Locate the '(' in the original source for signature extraction.
        final lineStart = src.indexOf(line);
        final openParen = lineStart >= 0 ? src.indexOf('(', lineStart) : -1;
        final sig = openParen >= 0 ? extractSignature(src, openParen) : null;
        if (sig == null) continue;
        final generics = methodMatch.group(3) ?? '';
        final args = buildArgs(sig, 1);
        final call = args.isEmpty
            ? '$effectiveName$generics()'
            : '$effectiveName$generics(${args.join(', ')})';
        final recvPrefix = dottedReceiver != null
            ? '$dottedReceiver.'
            : (effectiveReceiver.isEmpty ? '' : '$effectiveReceiver.');
        final bodyCall = '$recvPrefix$call';
        final prefix = 'mb.$name';
        add(
          prefix,
          'Call $rawName${sig.isEmpty ? '' : '($sig)'}',
          [bodyCall],
        );
        continue;
      }

      // Getters.
      final getterMatch = _getterRe.firstMatch(line);
      if (getterMatch != null) {
        final name = getterMatch.group(1)!;
        final nameLower = name.toLowerCase();
        if (name.startsWith('_') ||
            denylistedMethods.contains(nameLower) ||
            curatedAnchors.contains(nameLower)) {
          continue;
        }
        final getterReceiver = line.trimLeft().startsWith('static ')
            ? (staticReceiverFor(fileName) ?? '')
            : receiver;
        final recvPrefix = getterReceiver.isEmpty ? '' : '$getterReceiver.';
        add(
          'mb.get.$name',
          'Access $name',
          ['$recvPrefix$name'],
        );
        continue;
      }

      // Top-level functions.
      if (isTopLevel) {
        final fnMatch = _topLevelFnRe.firstMatch(line);
        if (fnMatch != null) {
          final name = fnMatch.group(1)!;
          final nameLower = name.toLowerCase();
          if (name.startsWith('_') ||
              denylistedMethods.contains(nameLower) ||
              curatedAnchors.contains(nameLower)) {
            continue;
          }
          final lineStart = src.indexOf(line);
          final openParen = lineStart >= 0 ? src.indexOf('(', lineStart) : -1;
          final sig = openParen >= 0 ? extractSignature(src, openParen) : null;
          if (sig == null) continue;
          final generics = fnMatch.group(2) ?? '';
          final args = buildArgs(sig, 1);
          final call = args.isEmpty
              ? '$name$generics()'
              : '$name$generics(${args.join(', ')})';
          add('mb.fn.$name', 'Call $name($sig)', [call]);
        }
      }
    }
  }

  // Sort for stable output: curated first (already inserted), then alpha.
  final sortedKeys = snippets.keys.toList()
    ..sort((a, b) {
      final aCurated = curated.containsKey(a) ? 0 : 1;
      final bCurated = curated.containsKey(b) ? 0 : 1;
      if (aCurated != bCurated) return aCurated - bCurated;
      return a.compareTo(b);
    });

  final output = <String, Object?>{
    for (final key in sortedKeys) key: snippets[key],
  };

  File(outPath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(output)}\n',
  );
  stdout.writeln('Generated ${snippets.length} snippets -> $outPath');
}
