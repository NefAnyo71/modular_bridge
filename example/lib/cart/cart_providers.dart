import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/core_providers.dart';
import 'cart_events.dart';
import 'cart_service.dart';

/// Riverpod Notifier driving the shopping cart items and reacting to domain events.
class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() {
    final bridge = ref.watch(bridgeProvider);
    final service = bridge.tryGet<CartService>();

    final clearedSub = bridge.on<CartClearedEvent>().listen((_) {
      state = const [];
    });

    final addedSub = bridge.on<CartItemAddedEvent>().listen((_) {
      final current = bridge.tryGet<CartService>();
      state = current != null ? List.of(current.items) : const [];
    });

    ref.onDispose(() {
      clearedSub.cancel();
      addedSub.cancel();
    });

    return service != null ? List.of(service.items) : const [];
  }

  void addItem(String name, double price) {
    final bridge = ref.read(bridgeProvider);
    final service = bridge.tryGet<CartService>();
    service?.addItem(name, price);
  }

  void clear() {
    final bridge = ref.read(bridgeProvider);
    final service = bridge.tryGet<CartService>();
    service?.clear();
  }
}

/// Provider exposing the shopping cart item list.
final cartProvider =
    NotifierProvider<CartNotifier, List<CartItem>>(CartNotifier.new);

/// Computed provider for cart item count.
final cartCountProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).length;
});

/// Computed provider for total cart price.
final cartTotalProvider = Provider<double>((ref) {
  return ref
      .watch(cartProvider)
      .fold(0.0, (sum, item) => sum + item.price);
});
