import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/parking_spot.dart';
import '../models/spot_report.dart';

/// 駐輪場データを端末内(SharedPreferences)に保存するリポジトリ。
/// 駐輪場の情報は更新頻度が低いため、サーバーを介さずローカルのみで完結させる。
/// 初回起動時は assets/seed_spots.json のサンプルデータを取り込む。
class SpotRepository {
  SpotRepository(this._prefs) {
    _ready = _load();
  }

  /// 通報がこの件数に達すると自動的に非表示(モデレーション)になる。
  static const int autoHideReportThreshold = 3;
  static const _storageKey = 'parking_spots_v1';
  static const _seedAssetPath = 'assets/seed_spots.json';

  final SharedPreferences _prefs;
  final _controller = StreamController<List<ParkingSpot>>.broadcast();
  List<ParkingSpot> _spots = [];
  late final Future<void> _ready;

  Future<void> _load() async {
    final raw = _prefs.getString(_storageKey);
    if (raw == null) {
      _spots = await _loadSeedSpots();
      await _persist();
    } else {
      final list = jsonDecode(raw) as List;
      _spots = list.map((e) => ParkingSpot.fromJson(e as Map<String, dynamic>)).toList();
    }
    _emit();
  }

  Future<List<ParkingSpot>> _loadSeedSpots() async {
    final raw = await rootBundle.loadString(_seedAssetPath);
    final list = jsonDecode(raw) as List;
    return list.map((e) => ParkingSpot.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _persist() {
    final raw = jsonEncode(_spots.map((s) => s.toJson()).toList());
    return _prefs.setString(_storageKey, raw);
  }

  bool _isVisible(ParkingSpot s) => s.status == SpotStatus.active && s.pricingType == PricingType.hourly;

  void _emit() {
    _controller.add(List.unmodifiable(_spots.where(_isVisible)));
  }

  /// 表示対象(非表示でない & 時間貸し)のスポットを購読する。
  /// 購読開始時に現在の一覧を即時に流したうえで、以降の変更を通知する。
  Stream<List<ParkingSpot>> watchActiveSpots() async* {
    await _ready;
    yield _spots.where(_isVisible).toList();
    yield* _controller.stream;
  }

  /// 現在の全スポット(非表示含む)のスナップショット。お気に入り等のID解決用。
  Future<List<ParkingSpot>> snapshot() async {
    await _ready;
    return List.unmodifiable(_spots);
  }

  /// ユーザーによる新規駐輪場の追加。
  Future<String> addSpot(ParkingSpot spot) async {
    await _ready;
    final id = const Uuid().v4();
    _spots.add(ParkingSpot(
      id: id,
      name: spot.name,
      address: spot.address,
      latitude: spot.latitude,
      longitude: spot.longitude,
      official: spot.official,
      conditions: spot.conditions,
      photoUrls: spot.photoUrls,
      streetViewUrl: spot.streetViewUrl,
      createdBy: spot.createdBy,
      createdAt: DateTime.now(),
    ));
    await _persist();
    _emit();
    return id;
  }

  /// ガセ情報・閉鎖済みの通報。一定数を超えると自動的に非表示にする。
  Future<void> reportSpot({
    required String spotId,
    required ReportReason reason,
    String? comment,
  }) async {
    await _updateSpot(spotId, (spot) {
      final nextCount = spot.reportCount + 1;
      return spot.copyWith(
        reportCount: nextCount,
        status: nextCount >= autoHideReportThreshold ? SpotStatus.hidden : spot.status,
      );
    });
  }

  Future<void> _updateSpot(String spotId, ParkingSpot Function(ParkingSpot) update) async {
    await _ready;
    final idx = _spots.indexWhere((s) => s.id == spotId);
    if (idx == -1) return;
    _spots[idx] = update(_spots[idx]);
    await _persist();
    _emit();
  }
}
