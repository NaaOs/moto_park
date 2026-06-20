import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/user_preferences.dart';

/// 設定画面: 表示テーマ(ダークモード)とマイバイク排気量を設定する。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  // マイバイクの排気量候補(0 = 未設定)。
  static const _ccOptions = [0, 50, 125, 250, 400, 750, 1000];

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UserPreferences>();

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionLabel('マイバイク(排気量)'),
          const Text(
            '登録すると、その排気量で停められない駐輪場を地図から自動で除外します。',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _ccOptions.map((cc) {
              final current = prefs.bikeDisplacementCc ?? 0;
              final selected = current == cc;
              return ChoiceChip(
                label: Text(cc == 0 ? '未設定' : '$cc cc'),
                selected: selected,
                onSelected: (_) => prefs.setBikeDisplacement(cc == 0 ? null : cc),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}
