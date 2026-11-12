import 'package:flutter/foundation.dart';

/// State management controller for the Home screen feed.
class HomeController extends ChangeNotifier {
  final List<String> _feedItems = [];
  String? _currentUserEmail;
  bool _isLoading = false;

  List<String> get feedItems => List.unmodifiable(_feedItems);
  String? get currentUserEmail => _currentUserEmail;
  bool get isLoading => _isLoading;

  /// Loads personalized feed items when a user logs in.
  Future<void> loadFeedForUser(String email) async {
    _isLoading = true;
    _currentUserEmail = email;
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 300));
    _feedItems.clear();
    _feedItems.addAll([
      'Welcome back, $email!',
      'Announcement: Modular architecture v1.0 released',
      'Architecture Tip: Zero-dependency DI reduces app payload size',
      'Event Bus: Decoupled listeners auto-disposed to prevent memory leaks',
    ]);
    _isLoading = false;
    notifyListeners();
  }

  /// Clears feed state when user logs out.
  void clearFeed() {
    _feedItems.clear();
    _currentUserEmail = null;
    notifyListeners();
  }
}

