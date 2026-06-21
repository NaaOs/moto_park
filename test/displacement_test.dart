import 'package:flutter_test/flutter_test.dart';
import 'package:motopark/models/parking_spot.dart';

void main() {
  group('deriveDisplacementRange', () {
    test('バイク種別を優先して範囲を導く', () {
      expect(deriveDisplacementRange(bikeType: '50cc以下'), (min: 0, max: 50));
      expect(deriveDisplacementRange(bikeType: '125cc以下'), (min: 0, max: 125));
      expect(deriveDisplacementRange(bikeType: '126cc以上'), (min: 126, max: 0));
    });

    test('車両制限の文章から排気量部分を抽出する', () {
      expect(
        deriveDisplacementRange(vehicleRestriction: '126cc以上。長さ2.2m以下、幅1.0m以下。'),
        (min: 126, max: 0),
      );
      expect(
        deriveDisplacementRange(vehicleRestriction: '排気量50cc以下は不可'),
        (min: 51, max: 0),
      );
      expect(
        deriveDisplacementRange(vehicleRestriction: '排気量による制限はありません。'),
        (min: 0, max: 0),
      );
    });

    test('データが無ければ制限なし', () {
      expect(deriveDisplacementRange(), (min: 0, max: 0));
      expect(deriveDisplacementRange(bikeType: '', vehicleRestriction: ''), (min: 0, max: 0));
    });
  });

  group('SpotConditions.accepts', () {
    test('上限ありの場合', () {
      const c = SpotConditions(maxDisplacementCc: 125);
      expect(c.accepts(50), true);
      expect(c.accepts(125), true);
      expect(c.accepts(250), false);
    });

    test('下限ありの場合', () {
      const c = SpotConditions(minDisplacementCc: 126);
      expect(c.accepts(50), false);
      expect(c.accepts(125), false);
      expect(c.accepts(400), true);
    });

    test('制限なしは全て受け入れる', () {
      const c = SpotConditions();
      expect(c.accepts(50), true);
      expect(c.accepts(1000), true);
    });
  });

  test('displacementLabel', () {
    expect(displacementLabel(0, 0), '排気量制限なし');
    expect(displacementLabel(126, 0), '126cc以上');
    expect(displacementLabel(0, 125), '125cc以下');
    expect(displacementLabel(126, 400), '126〜400cc');
  });
}
