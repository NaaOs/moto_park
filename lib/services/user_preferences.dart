import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/parking_spot.dart';

/// ユーザー設定(お気に入り・最近見た)を端末内(SharedPreferences)に保存する。
/// 変更時に listener へ通知する。
///
/// お気に入り・最近見たはID参照だが、ライブ取得でしか得られないスポット
/// (harvest後に追加された駐輪場など)はIDから実体を解決できないため、
/// 登録時点のスポット本体もキャッシュしておき、保存画面で参照できるようにする。
class UserPreferences extends ChangeNotifier {
  UserPreferences(this._prefs) {
    _load();
  }

  static const _kFavorites = 'pref_favorites';
  static const _kRecent = 'pref_recent';
  static const _kSpotCache = 'pref_spot_cache';
  static const _recentLimit = 20;

  final SharedPreferences _prefs;

  final List<String> _favorites = [];
  final List<String> _recent = []; // 先頭が最新
  final Map<String, ParkingSpot> _spotCache = {};

  List<String> get favorites => List.unmodifiable(_favorites);
  List<String> get recent => List.unmodifiable(_recent);

  /// お気に入り・最近見た登録時にキャッシュしたスポット本体(ID→スポット)。
  Map<String, ParkingSpot> get cachedSpots => Map.unmodifiable(_spotCache);

  void _load() {
    _favorites
      ..clear()
      ..addAll(_prefs.getStringList(_kFavorites) ?? const []);
    _recent
      ..clear()
      ..addAll(_prefs.getStringList(_kRecent) ?? const []);
    final cacheRaw = _prefs.getString(_kSpotCache);
    if (cacheRaw != null) {
      try {
        final map = jsonDecode(cacheRaw) as Map<String, dynamic>;
        _spotCache
          ..clear()
          ..addAll(map.map((k, v) =>
              MapEntry(k, ParkingSpot.fromJson(v as Map<String, dynamic>))));
      } catch (_) {
        // キャッシュが壊れていても機能自体は動く(同梱データから解決できる分は出る)。
      }
    }
  }

  /// お気に入り・最近見たから参照されなくなったキャッシュを削除して永続化する。
  Future<void> _persistCache() {
    _spotCache.removeWhere((id, _) => !_favorites.contains(id) && !_recent.contains(id));
    final raw = jsonEncode(_spotCache.map((k, v) => MapEntry(k, v.toJson())));
    return _prefs.setString(_kSpotCache, raw);
  }

  // ── お気に入り ──
  bool isFavorite(String id) => _favorites.contains(id);

  Future<void> toggleFavorite(ParkingSpot spot) async {
    if (_favorites.contains(spot.id)) {
      _favorites.remove(spot.id);
    } else {
      _favorites.insert(0, spot.id);
      _spotCache[spot.id] = spot;
    }
    await _prefs.setStringList(_kFavorites, _favorites);
    await _persistCache();
    notifyListeners();
  }

  // ── 最近見た ──
  Future<void> addRecent(ParkingSpot spot) async {
    _recent.remove(spot.id);
    _recent.insert(0, spot.id);
    _spotCache[spot.id] = spot;
    if (_recent.length > _recentLimit) {
      _recent.removeRange(_recentLimit, _recent.length);
    }
    await _prefs.setStringList(_kRecent, _recent);
    await _persistCache();
    notifyListeners();
  }

  Future<void> clearRecent() async {
    _recent.clear();
    await _prefs.setStringList(_kRecent, _recent);
    await _persistCache();
    notifyListeners();
  }
}
