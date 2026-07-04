import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/parking_spot.dart';
import '../models/spot_report.dart';

/// 駐輪場データを端末内(SharedPreferences)に保存するリポジトリ。
/// 駐輪場の情報は更新頻度が低いため、サーバーを介さずローカルのみで完結させる。
///
/// 通報は同梱データ・ライブ取得分を含む全スポットを対象に、この端末内で
/// ID単位に記録する(1スポットにつき1回)。「閉鎖」「バイク駐輪場ではない」の
/// 通報は、その場でこの端末の地図から非表示にする(取り消し可)。
class SpotRepository {
  SpotRepository(this._prefs) {
    _ready = _load();
  }

  static const _storageKey = 'parking_spots_v1';
  static const _reportsKey = 'spot_reports_v1';
  static const _hiddenKey = 'hidden_spots_v1';

  final SharedPreferences _prefs;
  final _controller = StreamController<List<ParkingSpot>>.broadcast();
  List<ParkingSpot> _spots = [];
  // 通報済みスポット(ID→通報理由)。乱用防止のため同一スポットへの通報は1回まで。
  Map<String, String> _reports = {};
  // 通報によりこの端末で非表示にしたスポットID。
  Set<String> _hiddenIds = {};
  late final Future<void> _ready;

  Future<void> _load() async {
    final raw = _prefs.getString(_storageKey);
    if (raw == null) {
      _spots = [];
    } else {
      final list = jsonDecode(raw) as List;
      _spots = list.map((e) => ParkingSpot.fromJson(e as Map<String, dynamic>)).toList();
      // 過去バージョンが初回起動時に取り込んでいたサンプルデータ(seed-*)は
      // 実在しない駐輪場のため、永続化済みのものも起動時に取り除く。
      final before = _spots.length;
      _spots.removeWhere((s) => s.id.startsWith('seed-'));
      if (_spots.length != before) await _persist();
    }
    final reportsRaw = _prefs.getString(_reportsKey);
    if (reportsRaw != null) {
      _reports = (jsonDecode(reportsRaw) as Map).map((k, v) => MapEntry(k as String, v as String));
    }
    _hiddenIds = (_prefs.getStringList(_hiddenKey) ?? const []).toSet();
    _emit();
  }

  Future<void> _persist() {
    final raw = jsonEncode(_spots.map((s) => s.toJson()).toList());
    return _prefs.setString(_storageKey, raw);
  }

  Future<void> _persistReports() async {
    await _prefs.setString(_reportsKey, jsonEncode(_reports));
    await _prefs.setStringList(_hiddenKey, _hiddenIds.toList());
  }

  bool _isVisible(ParkingSpot s) =>
      s.status == SpotStatus.active && s.pricingType == PricingType.hourly && !isHidden(s.id);

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

  /// このスポットを通報済みか(同一スポットへの通報は1回まで)。
  bool hasReported(String spotId) => _reports.containsKey(spotId);

  /// 通報によりこの端末で非表示になっているか。同梱データ・ライブ取得分にも効く。
  bool isHidden(String spotId) => _hiddenIds.contains(spotId);

  /// ガセ情報・閉鎖済みの通報。同梱データ・ライブ取得分を含む全スポットが対象。
  /// 「閉鎖」「バイク駐輪場ではない」はこの端末の地図から即時に非表示にする。
  Future<ReportOutcome> reportSpot({
    required String spotId,
    required ReportReason reason,
  }) async {
    await _ready;
    if (hasReported(spotId)) return ReportOutcome.alreadyReported;
    _reports[spotId] = reason.name;
    final shouldHide =
        reason == ReportReason.closed || reason == ReportReason.notMotorcycleParking;
    if (shouldHide) _hiddenIds.add(spotId);
    await _persistReports();
    _emit();
    return shouldHide ? ReportOutcome.hidden : ReportOutcome.recorded;
  }

  /// 通報による非表示を取り消す(通報記録ごと戻す)。SnackBarの「元に戻す」用。
  Future<void> undoReport(String spotId) async {
    await _ready;
    _reports.remove(spotId);
    _hiddenIds.remove(spotId);
    await _persistReports();
    _emit();
  }
}
