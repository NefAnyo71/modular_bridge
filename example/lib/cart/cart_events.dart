import 'package:modular_bridge/modular_bridge.dart';

/// Sealed base class for cart-related domain events.
sealed class CartEvent extends BridgeEvent {
  CartEvent();
}

/// Fired when an item is added to the shopping cart.
final class CartItemAddedEvent extends CartEvent {
  CartItemAddedEvent({
    required this.productName,
    required this.price,
    required this.totalItems,
  });

  final String productName;
  final double price;
  final int totalItems;

  @override
  String toString() =>
      'CartItemAddedEvent("$productName", \$$price, totalCount: $totalItems)';
}

/// Fired when the entire cart is cleared.
final class CartClearedEvent extends CartEvent {
  CartClearedEvent({required this.reason});

  final String reason;

  @override
  String toString() => 'CartClearedEvent(reason: "$reason")';
}

