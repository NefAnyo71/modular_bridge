import 'package:flutter/foundation.dart';
import 'package:modular_bridge/modular_bridge.dart';
import 'cart_events.dart';

/// Single item in the shopping cart.
class CartItem {
  const CartItem({
    required this.id,
    required this.name,
    required this.price,
  });

  final String id;
  final String name;
  final double price;
}

/// Service managing cart items, calculating totals, and broadcasting cart events.
class CartService extends ChangeNotifier {
  CartService(this._bridge);

  final ModularBridge _bridge;
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);
  int get itemCount => _items.length;
  double get totalPrice => _items.fold(0.0, (sum, item) => sum + item.price);

  /// Adds a product to the cart and broadcasts [CartItemAddedEvent].
  void addItem(String name, double price) {
    final item = CartItem(
      id: 'cart_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      price: price,
    );
    _items.add(item);
    notifyListeners();

    _bridge.publish(
      CartItemAddedEvent(
        productName: name,
        price: price,
        totalItems: _items.length,
      ),
    );
  }

  /// Clears all cart items and broadcasts [CartClearedEvent].
  void clear({String reason = 'Manual clear'}) {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();

    _bridge.publish(CartClearedEvent(reason: reason));
  }
}

