import 'dart:async';

/// Encapsulates a listener's connection to the [BridgeEventBus].
///
/// Provides convenient cancellation and state introspection to prevent memory leaks.
final class BridgeSubscription {
  /// Internal constructor wrapping a standard [StreamSubscription].
  BridgeSubscription(
    this._subscription, {
    this.ownerId,
    this.eventType,
    void Function(BridgeSubscription subscription)? onCancel,
  }) : _onCancel = onCancel;

  final StreamSubscription<dynamic> _subscription;
  final void Function(BridgeSubscription subscription)? _onCancel;

  /// Optional identifier representing the subscriber or owning module.
  final String? ownerId;

  /// The [BridgeEvent] type this subscription listens to, when known.
  ///
  /// Assigned automatically by [BridgeEventBus.subscribe]; `null` for
  /// manually constructed subscriptions.
  final Type? eventType;

  bool _isCanceled = false;

  /// Whether this subscription has been canceled.
  bool get isCanceled => _isCanceled;

  /// Whether the subscription is temporarily paused.
  bool get isPaused => _subscription.isPaused;

  /// Pauses the delivery of events.
  void pause([Future<void>? resumeSignal]) {
    if (!_isCanceled) {
      _subscription.pause(resumeSignal);
    }
  }

  /// Resumes the delivery of events.
  void resume() {
    if (!_isCanceled) {
      _subscription.resume();
    }
  }

  /// Cancels the subscription, stopping event reception and releasing resources.
  Future<void> cancel() async {
    if (_isCanceled) return;
    _isCanceled = true;
    _onCancel?.call(this);
    await _subscription.cancel();
  }
}
