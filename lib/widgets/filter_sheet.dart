import 'package:flutter/material.dart';

import '../models/spot_filter.dart';
import '../theme/app_theme.dart';

/// 詳細条件による絞り込み検索シート。
/// 「125cc以上可」「屋根あり」「地球ロック可」「アスファルト」「傾斜なし」など
/// 車にはないライダー特有の条件をワンタップで切り替えられるようにする(グローブ対応UI)。
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.initial});

  final SpotFilter initial;

  static Future<SpotFilter?> show(BuildContext context, SpotFilter current) {
    return showModalBottomSheet<SpotFilter>(
      context: context,
      isScrollControlled: true,
      // モバイルのタッチで「ドラッグして閉じる」操作が内部スクロールを
      // 奪ってしまい条件をスクロールできなくなるため、ドラッグ閉じを無効化する。
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FilterSheet(initial: current),
    );
  }

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late SpotFilter _filter;

  // 排気量フィルタ(JMPSAの区分に合わせる)。value=そのクラスの代表排気量で、
  // その排気量を受け入れる駐輪場のみ表示する。指定なしは全件表示。
  static const _ccOptions = <({String label, int? value})>[
    (label: '指定なし', value: null),
    (label: '50cc', value: 50),
    (label: '51cc~125cc', value: 125),
    (label: '126cc以上', value: 126),
  ];

  @override
  void initState() {
    super.initState();
    _filter = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    // 画面の高さに収めつつ、条件部分はスクロール・操作ボタンは下部固定にする。
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune, size: 28),
                  const SizedBox(width: 10),
                  Text('詳細条件で絞り込み', style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 16),
              // ── スクロール可能な条件エリア ──
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionLabel('排気量(あなたのバイク)'),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _ccOptions.map((opt) {
                          final selected = _filter.minDisplacementCc == opt.value;
                          return ChoiceChip(
                            label: Text(opt.label),
                            selected: selected,
                            onSelected: (_) => setState(() {
                              _filter = _filter.copyWith(
                                minDisplacementCc: opt.value,
                                clearMinDisplacementCc: opt.value == null,
                              );
                            }),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      _SectionLabel('予約の要否'),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          (label: '指定なし', value: null),
                          (label: '予約不要のみ', value: false),
                          (label: '予約制のみ', value: true),
                        ].map((opt) {
                          final selected = _filter.requiresReservation == opt.value;
                          return ChoiceChip(
                            label: Text(opt.label),
                            selected: selected,
                            onSelected: (_) => setState(() {
                              _filter = _filter.copyWith(
                                requiresReservation: opt.value,
                                clearRequiresReservation: opt.value == null,
                              );
                            }),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      _SectionLabel('その他の条件'),
                      _BigSwitchTile(
                        icon: Icons.roofing,
                        label: '屋根あり',
                        value: _filter.roofedOnly,
                        onChanged: (v) => setState(() => _filter = _filter.copyWith(roofedOnly: v)),
                      ),
                      _BigSwitchTile(
                        icon: Icons.lock_outline,
                        label: '地球ロック(固定物への施錠)可',
                        value: _filter.groundLockableOnly,
                        onChanged: (v) => setState(() => _filter = _filter.copyWith(groundLockableOnly: v)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // ── 下部固定の操作ボタン ──
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      onPressed: () => setState(() => _filter = const SpotFilter()),
                      child: const Text('条件をリセット'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      onPressed: () => Navigator.of(context).pop(_filter),
                      child: const Text('この条件で絞り込む'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _BigSwitchTile extends StatelessWidget {
  const _BigSwitchTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(!value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: value ? AppTheme.accent.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: value ? AppTheme.accent : Colors.black12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 26, color: value ? AppTheme.accent : Colors.black54),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
