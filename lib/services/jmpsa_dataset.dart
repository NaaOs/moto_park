import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

import '../models/parking_spot.dart';

/// harvest 済みの全国駐輪場データ(assets/jmpsa_spots.json)と、
/// 商業施設併設のバイク駐輪場データ(assets/commercial_spots.json)を
/// 読み取り専用でメモリにロードするデータセット。
///
/// 約3.9万件・24MB規模のため SharedPreferences には保存せず、起動時に
/// アセットから一度だけ読み込む。JSONデコードは重いのでバックグラウンド
/// isolate(compute)で行い、UIスレッドのジャンクを避ける。
/// 地図表示は MapScreen 側でビューポート内に絞り込む。
class JmpsaDataset {
  static const _assetPath = 'assets/jmpsa_spots.json';
  // tool/harvest_commercial.py で生成(OpenStreetMap + 各施設の公式サイト)。
  static const _commercialAssetPath = 'assets/commercial_spots.json';

  List<ParkingSpot>? _cache;
  Future<List<ParkingSpot>>? _loading;

  /// 全国データを読み込む(2回目以降はキャッシュを返す)。
  /// アセットが無い・壊れている場合は空リストを返し、アプリ動作を妨げない。
  Future<List<ParkingSpot>> loadAll() {
    if (_cache != null) return Future.value(_cache);
    return _loading ??= _load();
  }

  Future<List<ParkingSpot>> _load() async {
    // 片方のアセットが壊れていても、もう片方は表示できるよう個別に読み込む。
    final results = await Future.wait([
      _loadAsset(_assetPath),
      _loadAsset(_commercialAssetPath),
    ]);
    final spots = List<ParkingSpot>.unmodifiable(results.expand((e) => e));
    _cache = spots;
    return spots;
  }

  Future<List<ParkingSpot>> _loadAsset(String path) async {
    try {
      final raw = await rootBundle.loadString(path);
      return await compute(_parseSpots, raw);
    } catch (_) {
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
