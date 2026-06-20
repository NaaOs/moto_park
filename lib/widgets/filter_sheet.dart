import 'package:flutter/material.dart';

import '../models/parking_spot.dart';
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

  static const _ccOptions = [0, 125, 250, 400];

  @override
  void initState() {
    super.initState();
    _filter = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
            const SizedBox(height: 20),
            _SectionLabel('排気量'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _ccOptions.map((cc) {
                final selected = _filter.minDisplacementCc == (cc == 0 ? null : cc);
                return ChoiceChip(
                  label: Text(cc == 0 ? '指定なし' : '$cc cc以上可'),
                  selected: selected,
                  onSelected: (_) => setState(() {
                    _filter = _filter.copyWith(
                      minDisplacementCc: cc == 0 ? null : cc,
                      clearMinDisplacementCc: cc == 0,
                    );
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            _SectionLabel('路面状況(土・砂利は転倒リスクあり)'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [null, GroundSurface.asphalt, GroundSurface.gravel, GroundSurface.soil].map((s) {
                final selected = _filter.surface == s;
                return ChoiceChip(
                  label: Text(s == null ? '指定なし' : _surfaceLabel(s)),
                  selected: selected,
                  onSelected: (_) => setState(() {
                    _filter = _filter.copyWith(surface: s, clearSurface: s == null);
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
            _BigSwitchTile(
              icon: Icons.horizontal_rule,
              label: '傾斜なし',
              value: _filter.flatOnly,
              onChanged: (v) => setState(() => _filter = _filter.copyWith(flatOnly: v)),
            ),
            const SizedBox(height: 12),
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
                    onPressed: () => Navigator.of(context).pop(_filter),
                    child: const Text('この条件で絞り込む'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _surfaceLabel(GroundSurface s) {
    switch (s) {
      case GroundSurface.asphalt:
        return 'アスファルト';
      case GroundSurface.gravel:
        return '砂利';
      case GroundSurface.soil:
        return '土';
      case GroundSurface.unknown:
        return '不明';
    }
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
