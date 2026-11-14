import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:modular_bridge/modular_bridge.dart';

/// Read-only DevTools-style inspector for a [ModularBridge] container.
///
/// Displays live diagnostics — registrations, modules, scopes, resolution
/// metrics, and a rolling feed of [DependencyRegistrationEvent]s — and
/// offers an optional module health-check action.
///
/// Built on `package:flutter/widgets.dart` only (no Material dependency).
/// The widget refreshes automatically whenever a dependency registration
/// event is emitted; use the refresh button for metrics/health updates.
class ModularBridgeInspector extends StatefulWidget {
  /// Creates a [ModularBridgeInspector].
  ///
  /// [bridge] defaults to [ModularBridge.instance]. Set [showHealthCheck]
  /// to `false` to hide the health-check button (e.g. in release builds).
  const ModularBridgeInspector({
    super.key,
    this.bridge,
    this.showHealthCheck = true,
    this.maxEvents = 50,
  });

  /// The bridge to inspect. Defaults to [ModularBridge.instance].
  final ModularBridge? bridge;

  /// Whether to show the "Health Check" action.
  final bool showHealthCheck;

  /// Maximum number of recent dependency events kept in the feed.
  final int maxEvents;

  @override
  State<ModularBridgeInspector> createState() => _ModularBridgeInspectorState();
}

class _ModularBridgeInspectorState extends State<ModularBridgeInspector> {
  static const Color _green = Color(0xFF2E7D32);
  static const Color _red = Color(0xFFC62828);
  static const Color _orange = Color(0xFFEF6C00);
  static const Color _grey = Color(0xFF757575);
  static const Color _cardColor = Color(0xFFFFFFFF);
  static const Color _borderColor = Color(0xFFDDDDDD);

  late ModularBridge _bridge;
  StreamSubscription<DependencyRegistrationEvent>? _eventsSub;

  BridgeDiagnosticsReport? _report;
  List<ModuleHealthResult>? _healthResults;
  bool _healthRunning = false;
  final List<DependencyRegistrationEvent> _events = [];

  @override
  void initState() {
    super.initState();
    _bridge = widget.bridge ?? ModularBridge.instance;
    _eventsSub = _bridge.onDependencyEvents.listen(_onEvent);
    _refreshReport();
  }

  @override
  void didUpdateWidget(ModularBridgeInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.bridge ?? ModularBridge.instance;
    if (!identical(next, _bridge)) {
      unawaited(_eventsSub?.cancel());
      _bridge = next;
      _eventsSub = _bridge.onDependencyEvents.listen(_onEvent);
      _events.clear();
      _refreshReport();
    }
  }

  @override
  void dispose() {
    unawaited(_eventsSub?.cancel());
    super.dispose();
  }

  void _onEvent(DependencyRegistrationEvent event) {
    setState(() {
      _events.insert(0, event);
      if (_events.length > widget.maxEvents) {
        _events.removeRange(widget.maxEvents, _events.length);
      }
      _refreshReport();
    });
  }

  void _refreshReport() {
    _report = _bridge.diagnosticsReport();
  }

  void _refresh() {
    setState(_refreshReport);
  }

  Future<void> _runHealthCheck() async {
    setState(() => _healthRunning = true);
    try {
      final results = await _bridge.checkModuleHealth();
      if (mounted) setState(() => _healthResults = results);
    } finally {
      if (mounted) setState(() => _healthRunning = false);
    }
  }

  TextStyle _titleStyle(BuildContext context) => const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Color(0xFF212121),
      );

  TextStyle _bodyStyle(BuildContext context,
          {Color color = const Color(0xFF424242), double fontSize = 12}) =>
      TextStyle(fontSize: fontSize, color: color);

  Widget _actionLabel(
    BuildContext context, {
    required String text,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: onTap == null ? _grey : const Color(0xFF1565C0),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    if (report == null) {
      return const Center(child: Text('Loading…'));
    }
    final metrics = _bridge.metrics;
    final hitRatio = (metrics.cacheHitRatio * 100).toStringAsFixed(1);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'Bridge Diagnostics',
          titleStyle: _titleStyle(context),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showHealthCheck)
                _actionLabel(
                  context,
                  text: _healthRunning ? 'Checking…' : 'Health Check',
                  onTap: _healthRunning ? null : _runHealthCheck,
                ),
              _actionLabel(context, text: 'Refresh', onTap: _refresh),
            ],
          ),
          children: [
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                _MetricChip(
                    label: 'Environment',
                    value: _bridge.config.environment.name,
                    labelStyle: _bodyStyle(context, color: _grey, fontSize: 11),
                    valueStyle: _titleStyle(context)),
                _MetricChip(
                    label: 'Resolutions',
                    value: '${metrics.totalResolutions}',
                    labelStyle: _bodyStyle(context, color: _grey, fontSize: 11),
                    valueStyle: _titleStyle(context)),
                _MetricChip(
                    label: 'Cache Hits',
                    value: '${metrics.totalCacheHits}',
                    labelStyle: _bodyStyle(context, color: _grey, fontSize: 11),
                    valueStyle: _titleStyle(context)),
                _MetricChip(
                    label: 'Failures',
                    value: '${metrics.totalFailures}',
                    labelStyle: _bodyStyle(context, color: _grey, fontSize: 11),
                    valueStyle: _titleStyle(context)),
                _MetricChip(
                    label: 'Hit Ratio',
                    value: '$hitRatio%',
                    labelStyle: _bodyStyle(context, color: _grey, fontSize: 11),
                    valueStyle: _titleStyle(context)),
                _MetricChip(
                    label: 'Subscriptions',
                    value: '${report.activeSubscriptionCount}',
                    labelStyle: _bodyStyle(context, color: _grey, fontSize: 11),
                    valueStyle: _titleStyle(context)),
              ],
            ),
            if (report.activeScopeNames.isNotEmpty ||
                report.scopeStack.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Scopes: ${report.activeScopeNames.join(', ')}'
                '${report.scopeStack.isNotEmpty ? ' • stack: ${report.scopeStack.join(' → ')}' : ''}',
                style: _bodyStyle(context, color: _grey),
              ),
            ],
            if (report.issues.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final issue in report.issues)
                Text('⚠ $issue', style: _bodyStyle(context, color: _red)),
            ],
          ],
        ),
        if (_healthResults != null)
          _Section(
            title: 'Module Health',
            titleStyle: _titleStyle(context),
            children: [
              if (_healthResults!.isEmpty)
                Text('No modules are currently registered.',
                    style: _bodyStyle(context)),
              for (final r in _healthResults!)
                _HealthRow(result: r, bodyStyle: _bodyStyle(context)),
            ],
          ),
        _Section(
          title: 'Modules (${report.moduleNames.length})',
          titleStyle: _titleStyle(context),
          children: [
            if (report.moduleNames.isEmpty)
              Text('No modules registered.', style: _bodyStyle(context)),
            for (final name in report.moduleNames)
              _ListRow(
                glyph: '▣',
                glyphColor: _grey,
                title: name,
                subtitle: null,
                bodyStyle: _bodyStyle(context),
              ),
          ],
        ),
        _Section(
          title: 'Registrations (${report.registrations.length})',
          titleStyle: _titleStyle(context),
          children: [
            if (report.registrations.isEmpty)
              Text('No dependencies registered.', style: _bodyStyle(context)),
            for (final info in report.registrations)
              _ListRow(
                glyph: info.isReady ? '✓' : '◌',
                glyphColor: info.isReady ? _green : _orange,
                title: info.key.toString(),
                subtitle: '${info.lifecycle.name}'
                    '${info.ownerModuleName != null ? ' • ${info.ownerModuleName}' : ''}'
                    '${info.scopeName != null ? ' • scope: ${info.scopeName}' : ''}'
                    '${info.hasInstance ? ' • instance' : ''}',
                bodyStyle: _bodyStyle(context),
              ),
          ],
        ),
        _Section(
          title: 'Recent Dependency Events (${_events.length})',
          titleStyle: _titleStyle(context),
          children: [
            if (_events.isEmpty)
              Text('No registration events yet.', style: _bodyStyle(context)),
            for (final e in _events)
              _ListRow(
                glyph: e.kind == DependencyChangeKind.registered ? '+' : '−',
                glyphColor:
                    e.kind == DependencyChangeKind.registered ? _green : _red,
                title: e.info.key.toString(),
                subtitle: '${e.kind.name}'
                    '${e.scopeName != null ? ' • scope: ${e.scopeName}' : ''}',
                bodyStyle: _bodyStyle(context),
              ),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.titleStyle,
    required this.children,
    this.trailing,
  });

  final String title;
  final TextStyle titleStyle;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _ModularBridgeInspectorState._cardColor,
        border: Border.all(color: _ModularBridgeInspectorState._borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: titleStyle),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.labelStyle,
    required this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle labelStyle;
  final TextStyle valueStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        Text(value, style: valueStyle),
      ],
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.glyph,
    required this.glyphColor,
    required this.title,
    required this.subtitle,
    required this.bodyStyle,
  });

  final String glyph;
  final Color glyphColor;
  final String title;
  final String? subtitle;
  final TextStyle bodyStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text(glyph,
                style: bodyStyle.copyWith(
                    color: glyphColor, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: bodyStyle.copyWith(color: const Color(0xFF212121))),
                if (subtitle != null)
                  Text(subtitle!,
                      style: bodyStyle.copyWith(
                          color: _ModularBridgeInspectorState._grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.result, required this.bodyStyle});

  final ModuleHealthResult result;
  final TextStyle bodyStyle;

  @override
  Widget build(BuildContext context) {
    return _ListRow(
      glyph: result.isHealthy ? '✓' : '✗',
      glyphColor: result.isHealthy
          ? _ModularBridgeInspectorState._green
          : _ModularBridgeInspectorState._red,
      title: result.moduleName,
      subtitle: result.error?.toString(),
      bodyStyle: bodyStyle,
    );
  }
}
