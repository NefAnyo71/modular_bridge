import 'package:flutter/foundation.dart';
import 'package:modular_bridge/modular_bridge.dart';

/// Representation of an event recorded in the live stream console.
class EventLogEntry {
  const EventLogEntry({
    required this.timestamp,
    required this.eventName,
    required this.summary,
  });

  final DateTime timestamp;
  final String eventName;
  final String summary;
}

/// Service that logs and monitors all decoupled events in real time.
class EventLogService extends ChangeNotifier {
  final List<EventLogEntry> _history = [];

  List<EventLogEntry> get history => List.unmodifiable(_history);

  /// Records a new incoming [BridgeEvent].
  void record(BridgeEvent event) {
    final entry = EventLogEntry(
      timestamp: event.timestamp,
      eventName: event.runtimeType.toString(),
      summary: event.toString(),
    );
    _history.insert(0, entry);
    if (_history.length > 50) {
      _history.removeLast();
    }
    notifyListeners();
  }

  /// Clears the recorded log history.
  void clear() {
    _history.clear();
    notifyListeners();
  }
}

/// Module that acts as an ambient observer across all modules.
final class AnalyticsModule extends FeatureModule {
  @override
  String get name => 'AnalyticsModule';

  @override
  void registerDependencies(ModularBridge bridge) {
    bridge.registerLazySingleton<EventLogService>(
      () => EventLogService(),
      onDispose: (service) => service.dispose(),
    );
  }

  @override
  void init(ModularBridge bridge) {
    final logService = bridge.get<EventLogService>();

    // Listen to ALL BridgeEvents across the entire application.
    // onError/onDone/cancelOnError are forwarded to the bus subscription.
    subscribe<BridgeEvent>(
      bridge,
      (event) => logService.record(event),
      onError: (error) => logService.record(_ErrorEvent('$error')),
      onDone: () {},
      cancelOnError: false,
    );
  }

  @override
  void warmup(ModularBridge bridge) {
    // Runs after owned registrations resolved: force-resolve the log
    // service and drop a synthetic marker into the console.
    bridge.get<EventLogService>().record(_WarmupMarker());
  }

  @override
  Future<bool> healthCheck(ModularBridge bridge) async {
    // Healthy as long as the event log service resolved.
    return bridge.tryGet<EventLogService>() != null;
  }
}

final class _WarmupMarker extends BridgeEvent {
  _WarmupMarker();

  @override
  String toString() => 'AnalyticsModule warmed up';
}

final class _ErrorEvent extends BridgeEvent {
  _ErrorEvent(this.message);
  final String message;

  @override
  String toString() => 'BusError($message)';
}
