import 'package:flutter_test/flutter_test.dart';
import 'package:motopark/models/parking_spot.dart';

void main() {
  test('details/remarks/reservationUrl がJSON往復で保持される', () {
    const spot = ParkingSpot(
      id: 'jmpsa-100',
      name: '【予約制：akippa】テスト',
      address: '東京都新宿区西新宿4-28-21',
      latitude: 35.69,
      longitude: 139.69,
      official: true,
      createdBy: 'jmpsa',
      details: {
        'TEL': '03-1234-5678',
        '駐車場形態': '時間貸',
        '利用可能時間': '8:30～20:30',
        '収容台数': '1台',
        '車両制限': '排気量による制限はありません。',
        '管理会社': 'akippa株式会社',
        '最終更新日': '2025年9月19日',
      },
      remarks: 'akippaのサイトよりご予約ください。',
      reservationUrl: 'https://www.akippa.com/parking/xxx',
    );

    final round = ParkingSpot.fromJson(spot.toJson());

    expect(round.tel, '03-1234-5678');
    expect(round.parkingType, '時間貸');
    expect(round.availableHours, '8:30～20:30');
    expect(round.capacity, '1台');
    expect(round.vehicleRestriction, '排気量による制限はありません。');
    expect(round.managementCompany, 'akippa株式会社');
    expect(round.lastUpdated, '2025年9月19日');
    expect(round.remarks, 'akippaのサイトよりご予約ください。');
    expect(round.reservationUrl, 'https://www.akippa.com/parking/xxx');
    expect(round.hasDetails, true);
  });

  test('詳細が無いスポットは details 等をJSONに出力しない', () {
    const spot = ParkingSpot(
      id: 'u-1',
      name: 'ユーザー投稿',
      address: '',
      latitude: 0,
      longitude: 0,
      createdBy: 'user',
    );
    final json = spot.toJson();
    expect(json.containsKey('details'), false);
    expect(json.containsKey('remarks'), false);
    expect(json.containsKey('reservationUrl'), false);
    expect(ParkingSpot.fromJson(json).hasDetails, false);
  });

  test('空の値を返すアクセサは null になる', () {
    const spot = ParkingSpot(
      id: 'x',
      name: 'n',
      address: '',
      latitude: 0,
      longitude: 0,
      createdBy: 'jmpsa',
      details: {'TEL': ''},
    );
    expect(spot.tel, isNull);
  });
}
