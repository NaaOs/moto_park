import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:motopark/main.dart';

void main() {
  testWidgets('起動直後にマップ画面(MotoPark)を表示する', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(MotoParkApp(prefs: prefs));
    await tester.pump();

    expect(find.text('MotoPark'), findsOneWidget);
  });
}
