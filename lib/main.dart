import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/map_screen.dart';
import 'services/jmpsa_dataset.dart';
import 'services/spot_repository.dart';
import 'services/user_preferences.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(MotoParkApp(prefs: prefs));
}

class MotoParkApp extends StatelessWidget {
  const MotoParkApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SpotRepository>(create: (_) => SpotRepository(prefs)),
        // 全国データは読み取り専用の共有シングルトン(MapScreen/保存画面で共用)。
        Provider<JmpsaDataset>(create: (_) => JmpsaDataset()),
        ChangeNotifierProvider<UserPreferences>(create: (_) => UserPreferences(prefs)),
      ],
      child: MaterialApp(
        title: 'MotoPark',
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        home: const MapScreen(),
      ),
    );
  }
}
