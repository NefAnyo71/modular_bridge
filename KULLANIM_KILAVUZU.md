# Modular Bridge - Türkçe Kullanım Kılavuzu 📖

Bu kılavuz, `modular_bridge` paketini mevcut veya yeni bir Flutter projesine nasıl entegre edeceğinizi adım adım ve en pratik şekilde anlatır.

---

## 📌 İçindekiler
1. [Neden setState Gördün? (State Management İlişkisi)](#1-neden-setstate-gördün-state-management-ilişkisi)
2. [Adım 1: Ortam ve Konfigürasyon Kurulumu (`BridgeConfig`)](#adım-1-ortam-ve-konfigürasyon-kurulumu-bridgeconfig)
3. [Adım 2: Özellik Modüllerini Tanımlama (`FeatureModule`)](#adım-2-özellik-modüllerini-tanımlama-featuremodule)
4. [Adım 3: Olay Tabanlı İletişim (`BridgeEventBus`)](#adım-3-olay-tabanlı-iletişim-bridgeeventbus)
5. [Adım 4: Uygulama Başlatma ve Flutter Ağacına Bağlama](#adım-4-uygulama-başlatma-ve-flutter-ağacına-bağlama)
6. [Adım 5: BLoC / Cubit / State Management Entegrasyonu](#adım-5-bloc--cubit--state-management-entegrasyonu)
7. [Adım 6: Test Yazarken Mock Nesne Kullanımı](#adım-6-test-yazarken-mock-nesne-kullanımı)

---

## 1. Neden setState Gördün? (State Management İlişkisi)

Kodları incelerken gördüğün `setState` kullanımları **iki amaca** hizmet eder:
1. **`ModularBridgeProvider` içinde:** Çalışma zamanında (runtime) DEV ortamından PROD ortamına geçildiğinde, Flutter'ın `InheritedWidget` mekanizmasını tetikleyip ağacı yeni URL ve konfigürasyonlarla yeniden oluşturmak içindir (Flutter'ın kendi `Theme` veya `MediaQuery` çalışma mantığının aynısıdır).
2. **`example` içindeki örnekte:** Örnek uygulamayı saf ve yalın tutmak, dışarıdan fazladan kütüphane (Bloc, Riverpod vb.) yüklememek için en temel Flutter UI fonksiyonu kullanılmıştır.

> **Önemli:** `modular_bridge` bir UI state management kütüphanesi değildir; bir **Mimari, DI ve İletişim Köprüsüdür**. Sen ekranlarında ve state yönetiminde **BLoC, Cubit, Riverpod, Signals veya ChangeNotifier** kullanabilirsin.

---

## Adım 1: Ortam ve Konfigürasyon Kurulumu (`BridgeConfig`)

Farklı ortamlar (`dev`, `staging`, `prod`) için URL, timeout ve anahtarlarını tanımla:

```dart
// lib/core/app_config.dart
import 'package:modular_bridge/modular_bridge.dart';

BridgeConfig createAppConfig() {
  return BridgeConfig(
    environment: BridgeEnvironment.dev, // Başlangıç ortamı
    commonValues: {
      'appName': 'BenimProjem',
    },
    environmentValues: {
      BridgeEnvironment.dev: {
        'apiBaseUrl': 'https://dev.api.benimprojem.com',
        'timeout': const Duration(seconds: 30),
        'enableLogging': true,
      },
      BridgeEnvironment.staging: {
        'apiBaseUrl': 'https://staging.api.benimprojem.com',
        'timeout': const Duration(seconds: 20),
        'enableLogging': true,
      },
      BridgeEnvironment.prod: {
        'apiBaseUrl': 'https://api.benimprojem.com',
        'timeout': const Duration(seconds: 10),
        'enableLogging': false,
      },
    },
  );
}
```

---

## Adım 2: Özellik Modüllerini Tanımlama (`FeatureModule`)

Her bağımsız modül (örneğin Auth, Sepet, Sipariş) kendi bağımlılıklarını izole bir şekilde tanımlar:

```dart
// lib/features/auth/auth_module.dart
import 'package:modular_bridge/modular_bridge.dart';

final class AuthModule extends FeatureModule {
  @override
  String get name => 'AuthModule';

  @override
  void registerDependencies(ModularBridge bridge) {
    // 1. Lazy Singleton: İlk istendiğinde belleğe yüklenir
    bridge.registerLazySingleton<AuthRepository>(() {
      final baseUrl = bridge.config.getString('apiBaseUrl');
      final timeout = bridge.config.getDuration('timeout');
      return AuthRepositoryImpl(baseUrl: baseUrl, timeout: timeout);
    });

    // 2. Factory: Her çağrıldığında yepyeni bir örnek üretir
    bridge.registerFactory<LoginUseCase>(() {
      return LoginUseCase(bridge.get<AuthRepository>());
    });
  }
}
```

---

## Adım 3: Olay Tabanlı İletişim (`BridgeEventBus`)

Modüller birbirini `import` etmeden haberleşir.

### 1. Olayı Tanımla:
```dart
// lib/features/auth/events/auth_events.dart
import 'package:modular_bridge/modular_bridge.dart';

final class UserLoggedOutEvent extends BridgeEvent {
  UserLoggedOutEvent({required this.userId});
  final String userId;
}
```

### 2. Olayı Fırlat (Auth Modülü İçinde):
```dart
void logoutUser() {
  // Çıkış yapıldıktan sonra tüm uygulamaya anons geç:
  ModularBridge.I.publish(UserLoggedOutEvent(userId: '123'));
}
```

### 3. Olayı Dinle (Sepet Modülü İçinde - Otomatik Dispose):
```dart
// lib/features/cart/cart_module.dart
import 'package:modular_bridge/modular_bridge.dart';

final class CartModule extends FeatureModule {
  @override
  String get name => 'CartModule';

  @override
  void registerDependencies(ModularBridge bridge) {
    bridge.registerLazySingleton<CartService>(() => CartServiceImpl());
  }

  @override
  void init(ModularBridge bridge) {
    final cartService = bridge.get<CartService>();

    // AuthModule'ü tanımadan anonsu dinle!
    // CartModule kaldırıldığında bu abonelik bellek sızıntısı olmadan OTOMATİK silinir:
    subscribe<UserLoggedOutEvent>(bridge, (event) {
      cartService.clearCart();
      print('Kullanıcı çıkış yaptı (${event.userId}), sepet temizlendi!');
    });
  }
}
```

---

## Adım 4: Uygulama Başlatma ve Flutter Ağacına Bağlama

`main.dart` dosyasında kökü `ModularBridgeProvider` ile sar:

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:modular_bridge/modular_bridge.dart';
import 'core/app_config.dart';
import 'features/auth/auth_module.dart';
import 'features/cart/cart_module.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Config'i ata
  ModularBridge.I.setConfig(createAppConfig());

  // 2. Modülleri sırasıyla kaydet
  await ModularBridge.I.registerModules([
    AuthModule(),
    CartModule(),
  ]);

  runApp(
    const ModularBridgeProvider(
      child: BenimUygulamam(),
    ),
  );
}

class BenimUygulamam extends StatelessWidget {
  const BenimUygulamam({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: AnaSayfa(),
    );
  }
}
```

---

## Adım 5: BLoC / Cubit / State Management Entegrasyonu

Widget ağacından bağımlılıklarını tek satırda çağırabilirsin:

```dart
class AnaSayfa extends StatelessWidget {
  const AnaSayfa({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. BuildContext üzerinden doğrudan servis al:
    final authRepo = context.get<AuthRepository>();

    // 2. Veya BLoC Provider içinde kullan:
    return BlocProvider(
      create: (context) => LoginCubit(
        loginUseCase: context.get<LoginUseCase>(),
      ),
      child: const LoginView(),
    );
  }
}
```

---

## Adım 6: Test Yazarken Mock Nesne Kullanımı

Unit test yazarken mock nesneleri tek satırda enjekte et:

```dart
// test/login_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:modular_bridge/modular_bridge.dart';

class MockAuthRepository implements AuthRepository {
  @override
  Future<void> login() async => true;
}

void main() {
  test('Giriş testi', () {
    final bridge = ModularBridge.createIsolated();

    // Gerçek bağımlılık yerine mock nesneyi TEK SATIRDA override et:
    bridge.override<AuthRepository>(MockAuthRepository());

    final repo = bridge.get<AuthRepository>();
    expect(repo, isA<MockAuthRepository>());
  });
}
```

---

## 🎯 Özet Kullanım Tablosu

| Yapmak İstediğin Şey | Kullanacağın Kod |
| :--- | :--- |
| Servise erişmek | `context.get<Servis>()` veya `bridge.get<Servis>()` |
| Event fırlatmak | `bridge.publish(BenimEventim())` |
| Event dinlemek (Otomatik Dispose) | `subscribe<BenimEventim>(bridge, (e) => ...)` |
| Ortam değiştirmek (DEV -> PROD) | `config.switchEnvironment(BridgeEnvironment.prod)` |
| Testte Mock ile değiştirmek | `bridge.override<Servis>(MockServis())` |
