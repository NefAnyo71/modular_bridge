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
  final Map<Type, BridgeEvent> _lastEvents = {};
  bool _isDisposed = false;

  /// Whether the event bus has been disposed.
  bool get isDisposed => _isDisposed;

  /// The number of currently active subscriptions.
  int get activeSubscriptionCount => _activeSubscriptions.length;

  /// Whether at least one active subscription listens to events of type [T].
  ///
  /// Note: this performs an exact-type match against the subscription's
  /// declared event type. Catch-all subscriptions on [BridgeEvent] receive
  /// every event but are **not** counted for specific types.
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
    _lastEvents[event.runtimeType] = event;
    _eventController.add(event);
  }

  /// Returns a [Stream] emitting only events of type [T].
  Stream<T> on<T extends BridgeEvent>() {
    if (_isDisposed) {
      return const Stream.empty();
    }
    return _eventController.stream.where((event) => event is T).cast<T>();
  }

  BridgeEvent? _latestMatching<T extends BridgeEvent>() {
    BridgeEvent? best;
    for (final event in _lastEvents.values) {
      if (event is T &&
          (best == null || event.timestamp.isAfter(best.timestamp))) {
        best = event;
      }
    }
    return best;
  }

  /// Returns a broadcast [Stream] that first replays the most recently
  /// published event assignable to [T] (if any), then continues with live
  /// events — similar to a BehaviorSubject.
  ///
  /// Each listener receives the replay independently at subscription time.
  Stream<T> onLatest<T extends BridgeEvent>() {
    if (_isDisposed) {
      return const Stream.empty();
    }
    return Stream<T>.multi((controller) {
      if (_isDisposed) {
        controller.closeSync();
        return;
      }
      final last = _latestMatching<T>();
      if (last != null) {
        controller.addSync(last as T);
      }
      final rawSub =
          _eventController.stream.where((event) => event is T).cast<T>().listen(
                controller.addSync,
                onError: controller.addErrorSync,
                onDone: controller.closeSync,
              );
      controller.onCancel = rawSub.cancel;
    });
  }

  /// Completes with the next published event of type [T].
  ///
  /// Throws a [TimeoutException] if [timeout] elapses before a matching
  /// event arrives. The underlying subscription is always cleaned up.
  Future<T> once<T extends BridgeEvent>({Duration? timeout}) async {
    final completer = Completer<T>();
    final subscription = subscribe<T>((event) {
      if (!completer.isCompleted) {
        completer.complete(event);
      }
    });

    Timer? timer;
    if (timeout != null) {
      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException(
              'Timed out after ${timeout.inMilliseconds}ms waiting for $T.',
              timeout,
            ),
          );
        }
      });
    }

    try {
      return await completer.future;
    } finally {
      timer?.cancel();
      await subscription.cancel();
    }
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
