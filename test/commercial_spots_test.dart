import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motopark/models/parking_spot.dart';

/// tool/harvest_commercial.py が生成する同梱データの妥当性チェック。
void main() {
  final raw = File('assets/commercial_spots.json').readAsStringSync();
  final spots = (jsonDecode(raw) as List)
      .map((e) => ParkingSpot.fromJson(e as Map<String, dynamic>))
      .toList();

  test('商業施設データが読み込め、すべて商業施設として扱われる', () {
    expect(spots, isNotEmpty);
    expect(spots.every((s) => s.isCommercial), true);
    expect(spots.every((s) => s.id.startsWith('commercial-')), true);
  });

  test('IDが重複しない(提携データのIDとも衝突しない)', () {
    final ids = spots.map((s) => s.id).toSet();
    expect(ids.length, spots.length);
  });

  test('座標が日本国内に収まり、施設名・情報源・参照URLを持つ', () {
    for (final s in spots) {
      expect(s.latitude, inInclusiveRange(20, 46), reason: s.id);
      expect(s.longitude, inInclusiveRange(122, 154), reason: s.id);
      expect(s.facilityName, isNotNull, reason: s.id);
      expect(s.dataSource, anyOf('施設公式サイト', 'OpenStreetMap'), reason: s.id);
      expect(s.infoUrl, startsWith('https://'), reason: s.id);
      expect(s.feeDescription, isNotEmpty, reason: s.id);
    }
  });
}
