import 'package:flutter_test/flutter_test.dart';
import 'package:motopark/models/parking_spot.dart';
import 'package:motopark/models/spot_filter.dart';

ParkingSpot _spot(String name) => ParkingSpot(
      id: name,
      name: name,
      address: '',
      latitude: 0,
      longitude: 0,
      createdBy: 'jmpsa',
    );

void main() {
  test('予約制は施設名から判定できる', () {
    expect(_spot('【予約制：akippa】◯◯駐車場').requiresReservation, true);
    expect(_spot('新宿駅西口駐車場').requiresReservation, false);
  });

  test('予約フィルタ: 指定なしは全件通す', () {
    const filter = SpotFilter();
    expect(filter.matches(_spot('【予約制：特P】A')), true);
    expect(filter.matches(_spot('B駐車場')), true);
    expect(filter.isActive, false);
  });

  test('予約フィルタ: 予約不要のみ', () {
    const filter = SpotFilter(requiresReservation: false);
    expect(filter.matches(_spot('【予約制：akippa】A')), false);
    expect(filter.matches(_spot('B駐車場')), true);
    expect(filter.isActive, true);
    expect(filter.activeCount, 1);
  });

  test('予約フィルタ: 予約制のみ', () {
    const filter = SpotFilter(requiresReservation: true);
    expect(filter.matches(_spot('【予約制：akippa】A')), true);
    expect(filter.matches(_spot('B駐車場')), false);
  });

  test('copyWith で予約条件を解除できる', () {
    const filter = SpotFilter(requiresReservation: true);
    final cleared = filter.copyWith(clearRequiresReservation: true);
    expect(cleared.requiresReservation, isNull);
    expect(cleared.isActive, false);
  });

  test('施設の種類フィルタ: 駐輪場のみ / 商業施設のみ', () {
    final parking = _spot('B駐車場');
    const commercial = ParkingSpot(
      id: 'commercial-x',
      name: 'イオンモール◯◯ バイク駐輪場',
      address: '',
      latitude: 0,
      longitude: 0,
      createdBy: 'commercial',
    );
    expect(commercial.isCommercial, true);
    expect(parking.source, SpotSource.parking);

    const onlyCommercial = SpotFilter(source: SpotSource.commercial);
    expect(onlyCommercial.matches(commercial), true);
    expect(onlyCommercial.matches(parking), false);
    expect(onlyCommercial.activeCount, 1);

    const onlyParking = SpotFilter(source: SpotSource.parking);
    expect(onlyParking.matches(commercial), false);
    expect(onlyParking.matches(parking), true);

    final cleared = onlyCommercial.copyWith(clearSource: true);
    expect(cleared.source, isNull);
    expect(cleared.isActive, false);
  });
}
