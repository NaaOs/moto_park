import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

import '../models/parking_spot.dart';

/// harvest 済みの全国JMPSA駐輪場データ(assets/jmpsa_spots.json)を
/// 読み取り専用でメモリにロードするデータセット。
///
/// 約3.9万件・24MB規模のため SharedPreferences には保存せず、起動時に
/// アセットから一度だけ読み込む。JSONデコードは重いのでバックグラウンド
/// isolate(compute)で行い、UIスレッドのジャンクを避ける。
/// 地図表示は MapScreen 側でビューポート内に絞り込む。
class JmpsaDataset {
  static const _assetPath = 'assets/jmpsa_spots.json';

  List<ParkingSpot>? _cache;
  Future<List<ParkingSpot>>? _loading;

  /// 全国データを読み込む(2回目以降はキャッシュを返す)。
  /// アセットが無い・壊れている場合は空リストを返し、アプリ動作を妨げない。
  Future<List<ParkingSpot>> loadAll() {
    if (_cache != null) return Future.value(_cache);
    return _loading ??= _load();
  }

  Future<List<ParkingSpot>> _load() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final spots = await compute(_parseSpots, raw);
      _cache = spots;
      return spots;
    } catch (_) {
      _cache = const [];
      return const [];
    }
  }
}

/// バックグラウンドisolateで実行されるJSONパース処理(トップレベル関数である必要がある)。
List<ParkingSpot> _parseSpots(String raw) {
  final list = jsonDecode(raw) as List;
  return list
      .map((e) => ParkingSpot.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}
