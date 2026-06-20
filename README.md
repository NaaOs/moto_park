# MotoPark

バイク専用・時間貸し駐輪場マップ(MVP)。

## 地図

地図表示には **Google Maps** ([`google_maps_flutter`](https://pub.dev/packages/google_maps_flutter)) を使用します。
利用には Google Cloud Console で取得した APIキー(Maps JavaScript API / Maps SDK for Android / Maps SDK for iOS を有効化)が必要です。
以下のプレースホルダー `YOUR_GOOGLE_MAPS_API_KEY` を取得したキーに置き換えてください。

- Web: [`web/index.html`](web/index.html)
- Android: [`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml)
- iOS: [`ios/Runner/AppDelegate.swift`](ios/Runner/AppDelegate.swift)

## データの保存方式

駐輪場データは更新頻度が低いため、外部バックエンド(Firebase等)を使わず
**端末内(SharedPreferences)に保存**します。

- 初回起動時に [`assets/seed_spots.json`](assets/seed_spots.json) のサンプルデータを取り込みます。
- データは [JMPSA(日本二輪車普及安全協会)の駐車場検索](https://www.jmpsa.or.jp/society/parking/) を参照し、
  **時間貸し駐輪場のみ**を地図にプロットします(月極駐車場は表示しません)。
- 新規登録・通報による非表示化はすべて端末内のデータを直接更新します。
- ログイン・ユーザー登録は不要です。
- データ管理の実体は [`lib/services/spot_repository.dart`](lib/services/spot_repository.dart) です。

## 起動方法

```bash
flutter pub get
flutter run -d chrome
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
