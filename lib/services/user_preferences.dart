import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ユーザー設定(テーマ・マイバイク排気量・お気に入り・最近見た)を
/// 端末内(SharedPreferences)に保存する。変更時に listener へ通知する。
class UserPreferences extends ChangeNotifier {
  UserPreferences(this._prefs) {
    _load();
  }

  static const _kBikeCc = 'pref_bike_cc';
  static const _kFavorites = 'pref_favorites';
  static const _kRecent = 'pref_recent';
  static const _recentLimit = 20;

  final SharedPreferences _prefs;

  int? _bikeDisplacementCc; // null = 未設定
  final List<String> _favorites = [];
  final List<String> _recent = []; // 先頭が最新

  int? get bikeDisplacementCc => _bikeDisplacementCc;
  List<String> get favorites => List.unmodifiable(_favorites);
  List<String> get recent => List.unmodifiable(_recent);

  void _load() {
    final cc = _prefs.getInt(_kBikeCc);
    _bikeDisplacementCc = (cc == null || cc <= 0) ? null : cc;
    _favorites
      ..clear()
      ..addAll(_prefs.getStringList(_kFavorites) ?? const []);
    _recent
      ..clear()
      ..addAll(_prefs.getStringList(_kRecent) ?? const []);
  }

  // ── マイバイク排気量 ──
  Future<void> setBikeDisplacement(int? cc) async {
    _bikeDisplacementCc = (cc == null || cc <= 0) ? null : cc;
    if (_bikeDisplacementCc == null) {
      await _prefs.remove(_kBikeCc);
    } else {
      await _prefs.setInt(_kBikeCc, _bikeDisplacementCc!);
    }
    notifyListeners();
  }

  // ── お気に入り ──
  bool isFavorite(String id) => _favorites.contains(id);

  Future<void> toggleFavorite(String id) async {
    if (_favorites.contains(id)) {
      _favorites.remove(id);
    } else {
      _favorites.insert(0, id);
    }
    await _prefs.setStringList(_kFavorites, _favorites);
    notifyListeners();
  }

  // ── 最近見た ──
  Future<void> addRecent(String id) async {
    _recent.remove(id);
    _recent.insert(0, id);
    if (_recent.length > _recentLimit) {
      _recent.removeRange(_recentLimit, _recent.length);
    }
    await _prefs.setStringList(_kRecent, _recent);
    notifyListeners();
  }

  Future<void> clearRecent() async {
    _recent.clear();
    await _prefs.setStringList(_kRecent, _recent);
    notifyListeners();
  }
}
