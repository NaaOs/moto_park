import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:motopark/models/parking_spot.dart';
import 'package:motopark/models/spot_report.dart';
import 'package:motopark/services/spot_repository.dart';

Map<String, dynamic> _spotJson(String id, {String name = 'テスト駐輪場'}) => {
      'id': id,
      'name': name,
      'address': '東京都千代田区1-1',
      'latitude': 35.0,
      'longitude': 139.0,
      'createdBy': 'anonymous',
    };

Future<SpotRepository> _repoWith(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  return SpotRepository(prefs);
}

void main() {
  test('通報: 閉鎖・駐輪場ではない は同梱データのIDでも非表示になる', () async {
    final repo = await _repoWith({});
    // リポジトリに存在しないID(同梱データ・ライブ取得分を想定)。
    const datasetId = 'jmpsa-1234';

    final outcome =
        await repo.reportSpot(spotId: datasetId, reason: ReportReason.closed);

    expect(outcome, ReportOutcome.hidden);
    expect(repo.isHidden(datasetId), isTrue);
    expect(repo.hasReported(datasetId), isTrue);
  });

  test('通報: 情報の誤りは記録のみで非表示にしない', () async {
    final repo = await _repoWith({});
    final outcome =
        await repo.reportSpot(spotId: 'jmpsa-1', reason: ReportReason.wrongInfo);

    expect(outcome, ReportOutcome.recorded);
    expect(repo.isHidden('jmpsa-1'), isFalse);
    expect(repo.hasReported('jmpsa-1'), isTrue);
  });

  test('通報: 同一スポットへの2回目は受け付けない(乱用防止)', () async {
    final repo = await _repoWith({});
    await repo.reportSpot(spotId: 'jmpsa-1', reason: ReportReason.wrongInfo);
    final second =
        await repo.reportSpot(spotId: 'jmpsa-1', reason: ReportReason.closed);

    expect(second, ReportOutcome.alreadyReported);
    expect(repo.isHidden('jmpsa-1'), isFalse);
  });

  test('通報の取り消しで非表示・通報記録の両方が戻る', () async {
    final repo = await _repoWith({});
    await repo.reportSpot(spotId: 'jmpsa-1', reason: ReportReason.closed);
    await repo.undoReport('jmpsa-1');

    expect(repo.isHidden('jmpsa-1'), isFalse);
    expect(repo.hasReported('jmpsa-1'), isFalse);
  });

  test('通報による非表示は永続化され、再起動後も有効', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = SpotRepository(prefs);
    await repo.reportSpot(spotId: 'jmpsa-9', reason: ReportReason.closed);

    // 同じストレージから作り直す(アプリ再起動を模す)。
    final restarted = SpotRepository(prefs);
    await restarted.snapshot(); // ロード完了を待つ
    expect(restarted.isHidden('jmpsa-9'), isTrue);
    expect(restarted.hasReported('jmpsa-9'), isTrue);
  });

  test('通報で非表示にしたスポットは watchActiveSpots に流れない', () async {
    final repo = await _repoWith({
      'parking_spots_v1': jsonEncode([_spotJson('user-1')]),
    });
    await repo.reportSpot(spotId: 'user-1', reason: ReportReason.closed);

    final visible = await repo.watchActiveSpots().first;
    expect(visible.where((s) => s.id == 'user-1'), isEmpty);
  });

  test('初回起動でサンプルデータを取り込まない', () async {
    final repo = await _repoWith({});
    final spots = await repo.snapshot();
    expect(spots, isEmpty);
  });

  test('過去バージョンが永続化したサンプルデータ(seed-*)を起動時に除去する', () async {
    final repo = await _repoWith({
      'parking_spots_v1': jsonEncode([
        _spotJson('seed-001', name: '架空のサンプル駐輪場'),
        _spotJson('user-1'),
      ]),
    });

    final spots = await repo.snapshot();
    expect(spots.map((ParkingSpot s) => s.id), ['user-1']);
  });
}
