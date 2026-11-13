import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_events.dart';
import '../core/core_providers.dart';
import 'home_controller.dart';

/// Immutable model representing Home screen feed state.
class HomeFeedState {
  const HomeFeedState({required this.items, required this.isLoading});
  final List<String> items;
  final bool isLoading;
}

/// Riverpod Notifier driving personalized home feed, decoupled from AuthModule.
class HomeFeedNotifier extends Notifier<HomeFeedState> {
  @override
  HomeFeedState build() {
    final bridge = ref.watch(bridgeProvider);
    final controller = bridge.tryGet<HomeController>();

    final loginSub = bridge.on<UserLoggedInEvent>().listen((e) async {
      state = HomeFeedState(items: state.items, isLoading: true);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      state = HomeFeedState(
        items: [
          'Welcome back, ${e.email}!',
          'Clean Architecture: ModularBridge decoupled event bus integration',
          'Riverpod 2.6: Pure reactive state management with zero setState',
          'Memory Safety: All subscriptions auto-disposed upon module unload',
        ],
        isLoading: false,
      );
    });

    final logoutSub = bridge.on<UserLoggedOutEvent>().listen((_) {
      state = const HomeFeedState(items: [], isLoading: false);
    });

    ref.onDispose(() {
      loginSub.cancel();
      logoutSub.cancel();
    });

    return HomeFeedState(
      items: controller?.feedItems ?? const [],
      isLoading: controller?.isLoading ?? false,
    );
  }
}

/// Provider exposing the home feed state.
final homeFeedProvider =
    NotifierProvider<HomeFeedNotifier, HomeFeedState>(HomeFeedNotifier.new);
