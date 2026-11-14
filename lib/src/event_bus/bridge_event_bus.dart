import 'dart:async';
import 'package:flutter/foundation.dart';
import 'bridge_event.dart';
import 'bridge_subscription.dart';

/// Central event bus enabling decoupled communication across feature modules.
///
/// Features:
/// - Fully type-safe event publishing and consumption.
/// - Scoped subscription tracking with automatic unsubscription to prevent memory leaks.
/// - Latest-event replay ([onLatest]) and one-shot waits ([once]).
/// - Zero external dependencies.
///
/// Memory note: the bus retains the most recent event of each published
/// runtime type for replay. Call [clearReplayHistory] to release those
/// references (e.g. when they may contain sensitive session data).
class BridgeEventBus {
  /// Creates a new [BridgeEventBus].
  ///
  /// Set [sync] to `true` for synchronous event delivery (events reach
  /// listeners before [publish] returns). The default `false` matches
  /// standard Dart broadcast stream semantics.
  BridgeEventBus({bool sync = false})
      : _eventController = StreamController<BridgeEvent>.broadcast(sync: sync);

  final StreamController<BridgeEvent> _eventController;
  final StreamController<void> _disposeController =
      StreamController<void>.broadcast();
  final List<BridgeSubscription> _activeSubscriptions = [];
  final Map<Type, _ReplayEntry> _lastEvents = {};
  int _publishSequence = 0;
  bool _isDisposed = false;

  /// Whether the event bus has been disposed.
  bool get isDisposed => _isDisposed;

  /// The number of currently active subscriptions.
  int get activeSubscriptionCount => _activeSubscriptions.length;

  /// Whether at least one active managed subscription listens to events of
  /// type [T].
  ///
  /// Matching is exact against the subscription's declared event type.
  /// Pass `includeCatchAll: true` to also count subscriptions declared on
  /// [BridgeEvent] itself, which receive every event. Note that only
  /// subscriptions created through [subscribe] are tracked — streams obtained
  /// via [on] or [onLatest] are not counted.
  bool hasListeners<T extends BridgeEvent>({bool includeCatchAll = false}) =>
      _activeSubscriptions.any(
        (sub) =>
            sub.eventType == T ||
            (includeCatchAll && sub.eventType == BridgeEvent),
      );

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
    _lastEvents[event.runtimeType] =
        _ReplayEntry(event: event, sequence: ++_publishSequence);
    _eventController.add(event);
  }

  /// Returns a [Stream] emitting only events of type [T].
  Stream<T> on<T extends BridgeEvent>() {
    if (_isDisposed) {
      return const Stream.empty();
    }
    return _eventController.stream.where((event) => event is T).cast<T>();
  }

  _ReplayEntry? _latestMatching<T extends BridgeEvent>() {
    _ReplayEntry? best;
    for (final entry in _lastEvents.values) {
      if (entry.event is T &&
          (best == null || entry.sequence > best.sequence)) {
        best = entry;
      }
    }
    return best;
  }

  /// Returns a broadcast [Stream] that first replays the most recently
  /// published event assignable to [T] (if any), then continues with live
  /// events — similar to a BehaviorSubject.
  ///
  /// Each listener receives the replay independently at subscription time.
  /// The replay/live boundary is sequence-guarded: an event published after
  /// the listener subscribed is delivered exactly once through the live
  /// stream and is never duplicated by the replay.
  Stream<T> onLatest<T extends BridgeEvent>() {
    if (_isDisposed) {
      return const Stream.empty();
    }
    return Stream<T>.multi((controller) {
      if (_isDisposed) {
        controller.closeSync();
        return;
      }
      // Subscribe first so no live event can be lost, then replay only
      // events published at or before the subscription marker.
      final marker = _publishSequence;
      final rawSub =
          _eventController.stream.where((event) => event is T).cast<T>().listen(
                controller.addSync,
                onError: controller.addErrorSync,
                onDone: controller.closeSync,
              );
      controller.onCancel = rawSub.cancel;

      final last = _latestMatching<T>();
      if (last != null && last.sequence <= marker) {
        controller.addSync(last.event as T);
      }
    });
  }

  /// Completes with the next published event of type [T].
  ///
  /// Throws a [TimeoutException] if [timeout] elapses before a matching
  /// event arrives, or a [StateError] if the bus is disposed while waiting.
  /// The underlying subscription is always cleaned up.
  Future<T> once<T extends BridgeEvent>({Duration? timeout}) async {
    final completer = Completer<T>();
    final subscription = subscribe<T>(
      (event) {
        if (!completer.isCompleted) {
          completer.complete(event);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('BridgeEventBus was disposed while waiting for $T.'),
          );
        }
      },
    );

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

    // StreamSubscription.cancel does not fire onDone, so disposal is
    // signalled through a dedicated broadcast instead.
    final disposeSub = _disposeController.stream.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('BridgeEventBus was disposed while waiting for $T.'),
        );
      }
    });

    try {
      return await completer.future;
    } finally {
      timer?.cancel();
      await disposeSub.cancel();
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

  /// Releases the retained latest-event references used by [onLatest].
  ///
  /// Live event delivery is unaffected; new listeners simply stop receiving
  /// a replay until the next matching publish.
  void clearReplayHistory() {
    _lastEvents.clear();
  }

  /// Completely disposes the event bus, canceling all subscriptions and closing the stream.
  ///
  /// Subscriptions canceled during disposal complete their `onDone`
  /// callbacks, so pending [once] waits finish with a [StateError] instead of
  /// hanging forever.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await clearSubscriptions();
    if (!_disposeController.isClosed) {
      _disposeController.add(null);
    }
    await _eventController.close();
    await _disposeController.close();
  }
}

/// Internal bookkeeping for replayable events: the event plus a monotonic
/// publish sequence used to order replay against live delivery.
final class _ReplayEntry {
  const _ReplayEntry({required this.event, required this.sequence});

  final BridgeEvent event;
  final int sequence;
}
