import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:modular_bridge/modular_bridge.dart';
import '../core/core_providers.dart';
import 'analytics_module.dart';

/// Riverpod Notifier driving the real-time event bus stream console.
class EventLogsNotifier extends Notifier<List<EventLogEntry>> {
  @override
  List<EventLogEntry> build() {
    final bridge = ref.watch(bridgeProvider);

    // Subscribes to ALL BridgeEvents across the entire application
    final sub = bridge.on<BridgeEvent>().listen((event) {
      final entry = EventLogEntry(
        timestamp: event.timestamp,
        eventName: event.runtimeType.toString(),
        summary: event.toString(),
      );
      state = [entry, ...state.take(49)];
    });

    ref.onDispose(sub.cancel);
    return const [];
  }

  /// Clears the console logs.
  void clear() {
    state = const [];
  }
}

/// Provider exposing the real-time event logs.
final eventLogsProvider =
    NotifierProvider<EventLogsNotifier, List<EventLogEntry>>(
  EventLogsNotifier.new,
);
