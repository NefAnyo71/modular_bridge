import 'dart:async';
import 'package:flutter/foundation.dart';
import 'bridge_event.dart';
import 'bridge_subscription.dart';

/// Central event bus enabling decoupled communication across feature modules.
///
/// Features:
/// - Fully type-safe event publishing and consumption.
/// - Scoped subscription tracking with automatic unsubscription to prevent memory leaks.
/// - Zero external dependencies.
class BridgeEventBus {
  /// Creates a new [BridgeEventBus].
  BridgeEventBus({bool sync = false})
      : _eventController = StreamController<BridgeEvent>.broadcast(sync: sync);

  final StreamController<BridgeEvent> _eventController;
  final List<BridgeSubscription> _activeSubscriptions = [];
  bool _isDisposed = false;

  /// Whether the event bus has been disposed.
  bool get isDisposed => _isDisposed;

  /// The number of currently active subscriptions.
  int get activeSubscriptionCount => _activeSubscriptions.length;

  /// Whether at least one active subscription listens to events of type [T].
  bool hasListeners<T extends BridgeEvent>() =>
      _activeSubscriptions.any((sub) => sub.eventType == T);

  /// Publishes a [BridgeEvent] to all active subscribers of type [T].
  void publish<T extends BridgeEvent>(T event) {
    if (_isDisposed) {
      if (kDebugMode) {
        debugPrint(
          '[BridgeEventBus] Attempted to publish event $event to a disposed bus.',
        );
      }
      return;
    }
    _eventController.add(event);
  }

  /// Returns a [Stream] emitting only events of type [T].
  Stream<T> on<T extends BridgeEvent>() {
    if (_isDisposed) {
      return const Stream.empty();
    }
    return _eventController.stream.where((event) => event is T).cast<T>();
  }

  /// Subscribes to events of type [T] with a managed [BridgeSubscription].
  ///
  /// The returned [BridgeSubscription] can be canceled manually or automatically
  /// when its [ownerId] (e.g. a [FeatureModule]) is disposed.
  BridgeSubscription subscribe<T extends BridgeEvent>(
    void Function(T event) onData, {
    String? ownerId,
    void Function(Object error)? onError,
    void Function()? onDone,
    bool cancelOnError = false,
  }) {
    if (_isDisposed) {
      throw StateError('Cannot subscribe to a disposed BridgeEventBus.');
    }

    final rawSub = on<T>().listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );

    late final BridgeSubscription bridgeSub;
    bridgeSub = BridgeSubscription(
      rawSub,
      ownerId: ownerId,
      eventType: T,
      onCancel: (sub) {
        _activeSubscriptions.remove(sub);
      },
    );

    _activeSubscriptions.add(bridgeSub);
    return bridgeSub;
  }

  /// Cancels all subscriptions created under the given [ownerId].
  Future<void> cancelSubscriptionsForOwner(String ownerId) async {
    final toCancel =
        _activeSubscriptions.where((sub) => sub.ownerId == ownerId).toList();

    for (final sub in toCancel) {
      await sub.cancel();
    }
  }

  /// Cancels all active subscriptions without closing the event controller.
  Future<void> clearSubscriptions() async {
    final copy = List<BridgeSubscription>.from(_activeSubscriptions);
    for (final sub in copy) {
      await sub.cancel();
    }
    _activeSubscriptions.clear();
  }

  /// Completely disposes the event bus, canceling all subscriptions and closing the stream.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await clearSubscriptions();
    await _eventController.close();
  }
}
