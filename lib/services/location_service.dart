import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// 現在地取得まわりをまとめたサービス。権限まわりの分岐をここに閉じ込める。
/// Windows デスクトップでは geolocator がプラットフォームスレッド外からメッセージを送り
/// クラッシュする既知の問題があるため、Windows の場合は位置情報を無効化する。
class LocationService {
  static bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<LatLng?> getCurrentLatLng() async {
    if (_isWindows) return null;
    if (!await _ensurePermission()) return null;
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return LatLng(position.latitude, position.longitude);
  }

  Stream<LatLng> watchPosition() async* {
    if (_isWindows) return;
    if (!await _ensurePermission()) return;
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).map((p) => LatLng(p.latitude, p.longitude));
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }
}
