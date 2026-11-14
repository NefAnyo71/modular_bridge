import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:modular_bridge/modular_bridge.dart';

import '../fixtures/test_fixtures.dart';

void main() {
  group('BridgeEventBus', () {
    late BridgeEventBus eventBus;

    setUp(() {
      eventBus = BridgeEventBus();
    });

    tearDown(() async {
      await eventBus.dispose();
    });

    test('publishes and receives strongly typed events', () async {
      final receivedLogins = <UserLoggedInEvent>[];
      final receivedLogouts = <UserLoggedOutEvent>[];

      eventBus.subscribe<UserLoggedInEvent>((e) => receivedLogins.add(e));
      eventBus.subscribe<UserLoggedOutEvent>((e) => receivedLogouts.add(e));

      eventBus.publish(UserLoggedInEvent(userId: 'u1', email: 'u1@test.com'));
      eventBus.publish(UserLoggedOutEvent(userId: 'u1'));
      eventBus.publish(OrderPlacedEvent(orderId: 'ord_999'));

      await Future<void>.delayed(Duration.zero);

      expect(receivedLogins.length, 1);
      expect(receivedLogins.first.userId, 'u1');
      expect(receivedLogouts.length, 1);
      expect(receivedLogouts.first.userId, 'u1');
    });

    test('on<T>() stream only emits events of the requested type', () async {
      final events = <String>[];
      final sub = eventBus.on<UserLoggedInEvent>().listen(
            (e) => events.add(e.email),
          );
      addTearDown(sub.cancel);

      eventBus.publish(UserLoggedInEvent(userId: 'u1', email: 'one@test.com'));
      eventBus.publish(UserLoggedOutEvent(userId: 'u1'));
      eventBus.publish(UserLoggedInEvent(userId: 'u2', email: 'two@test.com'));

      await Future<void>.delayed(Duration.zero);

      expect(events, ['one@test.com', 'two@test.com']);
    });

    test('canceling a BridgeSubscription stops event delivery', () async {
      var callCount = 0;
      final sub = eventBus.subscribe<UserLoggedInEvent>((_) => callCount++);

      eventBus.publish(UserLoggedInEvent(userId: '1', email: 'a@b.com'));
      await Future<void>.delayed(Duration.zero);
      expect(callCount, 1);

      await sub.cancel();
      expect(sub.isCanceled, isTrue);

      eventBus.publish(UserLoggedInEvent(userId: '2', email: 'c@d.com'));
      await Future<void>.delayed(Duration.zero);
      expect(callCount, 1); // Unchanged
    });

    test('cancels all subscriptions for a specific ownerId', () async {
      var mod1Count = 0;
      var mod2Count = 0;

      eventBus.subscribe<UserLoggedOutEvent>((_) => mod1Count++,
          ownerId: 'Module1');
      eventBus.subscribe<UserLoggedOutEvent>((_) => mod2Count++,
          ownerId: 'Module2');

      eventBus.publish(UserLoggedOutEvent(userId: '1'));
      await Future<void>.delayed(Duration.zero);
      expect(mod1Count, 1);
      expect(mod2Count, 1);

      // Cancel only Module1
      await eventBus.cancelSubscriptionsForOwner('Module1');

      eventBus.publish(UserLoggedOutEvent(userId: '2'));
      await Future<void>.delayed(Duration.zero);
      expect(mod1Count, 1); // Not called
      expect(mod2Count, 2); // Still called
    });

    test('hasListeners reports active subscriptions per event type', () async {
      expect(eventBus.hasListeners<UserLoggedInEvent>(), isFalse);

      final sub = eventBus.subscribe<UserLoggedInEvent>((_) {});
      expect(eventBus.hasListeners<UserLoggedInEvent>(), isTrue);
      expect(eventBus.hasListeners<UserLoggedOutEvent>(), isFalse);

      await sub.cancel();
      expect(eventBus.hasListeners<UserLoggedInEvent>(), isFalse);
    });

    test('activeSubscriptionCount reflects live subscriptions', () async {
      expect(eventBus.activeSubscriptionCount, 0);

      final sub1 = eventBus.subscribe<UserLoggedInEvent>((_) {});
      eventBus.subscribe<UserLoggedOutEvent>((_) {});
      expect(eventBus.activeSubscriptionCount, 2);

      await sub1.cancel();
      expect(eventBus.activeSubscriptionCount, 1);

      await eventBus.clearSubscriptions();
      expect(eventBus.activeSubscriptionCount, 0);
    });

    test('onLatest replays the most recent matching event to new listeners',
        () async {
      eventBus
          .publish(UserLoggedInEvent(userId: 'u1', email: 'first@test.com'));
      eventBus.publish(UserLoggedOutEvent(userId: 'u1'));
      eventBus
          .publish(UserLoggedInEvent(userId: 'u2', email: 'second@test.com'));

      final received = <String>[];
      final sub = eventBus.onLatest<UserLoggedInEvent>().listen(
            (e) => received.add(e.email),
          );
      addTearDown(sub.cancel);

      await Future<void>.delayed(Duration.zero);

      // Replays only the latest UserLoggedInEvent, not the logout in between.
      expect(received, ['second@test.com']);

      eventBus
          .publish(UserLoggedInEvent(userId: 'u3', email: 'third@test.com'));
      await Future<void>.delayed(Duration.zero);
      expect(received, ['second@test.com', 'third@test.com']);
    });

    test('onLatest emits nothing when no matching event was published',
        () async {
      final received = <UserLoggedInEvent>[];
      final sub = eventBus.onLatest<UserLoggedInEvent>().listen(received.add);
      addTearDown(sub.cancel);

      eventBus.publish(UserLoggedOutEvent(userId: 'u1'));
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
    });

    test('once completes with the next matching event', () async {
      final future = eventBus.once<UserLoggedInEvent>();
      eventBus.publish(UserLoggedOutEvent(userId: 'u1'));
      eventBus.publish(UserLoggedInEvent(userId: 'u1', email: 'once@test.com'));

      final event = await future;
      expect(event.email, 'once@test.com');
      expect(eventBus.activeSubscriptionCount, 0); // cleaned up
    });

    test('once times out with TimeoutException', () async {
      await expectLater(
        eventBus.once<UserLoggedInEvent>(
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(eventBus.activeSubscriptionCount, 0);
    });

    test('hasListeners supports catch-all subscriptions opt-in', () async {
      expect(eventBus.hasListeners<UserLoggedInEvent>(), isFalse);
      expect(
        eventBus.hasListeners<UserLoggedInEvent>(includeCatchAll: true),
        isFalse,
      );

      final sub = eventBus.subscribe<BridgeEvent>((_) {});
      addTearDown(sub.cancel);

      // Exact matching still excludes the catch-all by default.
      expect(eventBus.hasListeners<UserLoggedInEvent>(), isFalse);
      expect(
        eventBus.hasListeners<UserLoggedInEvent>(includeCatchAll: true),
        isTrue,
      );
      expect(eventBus.hasListeners<BridgeEvent>(includeCatchAll: true), isTrue);
    });

    test('onLatest does not duplicate events published right after subscribe',
        () async {
      final received = <String>[];
      final sub = eventBus.onLatest<UserLoggedInEvent>().listen(
            (e) => received.add(e.email),
          );
      addTearDown(sub.cancel);

      // Published after subscription: must arrive exactly once via live.
      eventBus.publish(UserLoggedInEvent(userId: 'u1', email: 'live@test.com'));
      await Future<void>.delayed(Duration.zero);

      expect(received, ['live@test.com']);
    });

    test('clearReplayHistory stops replays but keeps live delivery', () async {
      eventBus.publish(UserLoggedInEvent(userId: 'u1', email: 'old@test.com'));
      eventBus.clearReplayHistory();

      final received = <String>[];
      final sub = eventBus.onLatest<UserLoggedInEvent>().listen(
            (e) => received.add(e.email),
          );
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);

      eventBus.publish(UserLoggedInEvent(userId: 'u2', email: 'new@test.com'));
      await Future<void>.delayed(Duration.zero);
      expect(received, ['new@test.com']);
    });

    test('once completes with StateError when the bus is disposed', () async {
      final future = eventBus.once<UserLoggedInEvent>();
      await eventBus.dispose();

      await expectLater(future, throwsA(isA<StateError>()));
    });

    test('subscription cancel is idempotent and concurrency-safe', () async {
      final sub = eventBus.subscribe<UserLoggedInEvent>((_) {});

      await Future.wait([sub.cancel(), sub.cancel()]);
      await sub.cancel();

      expect(sub.isCanceled, isTrue);
      expect(eventBus.activeSubscriptionCount, 0);
    });

    test('disposed bus rejects new subscriptions and ignores publishes',
        () async {
      await eventBus.dispose();

      expect(eventBus.isDisposed, isTrue);
      expect(
        () => eventBus.subscribe<UserLoggedInEvent>((_) {}),
        throwsA(isA<StateError>()),
      );
      expect(eventBus.on<UserLoggedInEvent>(), emitsDone);

      // Publish must be a safe no-op, not a crash.
      eventBus.publish(UserLoggedInEvent(userId: '1', email: 'a@b.com'));
    });
  });
}
