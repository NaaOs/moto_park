import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../models/parking_spot.dart';
import '../services/spot_repository.dart';
import '../theme/app_theme.dart';

/// ユーザーによる新規駐輪場の登録画面。
/// 地図長押しで取得した座標を初期値に、ライダー特化の条件をチップで選択する。
class AddSpotScreen extends StatefulWidget {
  const AddSpotScreen({super.key, required this.initialLocation});

  final LatLng initialLocation;

  @override
  State<AddSpotScreen> createState() => _AddSpotScreenState();
}

class _AddSpotScreenState extends State<AddSpotScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _photoUrlController = TextEditingController();

  int _minCc = 0;
  bool _roofed = false;
  bool _groundLockable = false;
  bool _flat = false;
  GroundSurface _surface = GroundSurface.asphalt;
  bool _saving = false;

  static const _ccOptions = [0, 125, 250, 400];

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('名称を入力してください')));
      return;
    }
    setState(() => _saving = true);
    try {
      final photoUrl = _photoUrlController.text.trim();
      await context.read<SpotRepository>().addSpot(
            ParkingSpot(
              id: '',
              name: name,
              address: _addressController.text.trim(),
              latitude: widget.initialLocation.latitude,
              longitude: widget.initialLocation.longitude,
              official: false,
              conditions: SpotConditions(
                minDisplacementCc: _minCc,
                roofed: _roofed,
                groundLockable: _groundLockable,
                surface: _surface,
                flat: _flat,
              ),
              photoUrls: photoUrl.isEmpty ? const [] : [photoUrl],
              createdBy: 'anonymous',
            ),
          );
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('駐輪場を登録しました。みんなで育てる地図にご協力ありがとうございます！')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('登録に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('駐輪場を新規登録')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.my_location, color: AppTheme.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '登録地点: ${widget.initialLocation.latitude.toStringAsFixed(5)}, '
                      '${widget.initialLocation.longitude.toStringAsFixed(5)}\n'
                      '(地図を長押しした位置が登録されます)',
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(labelText: '名称 *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(labelText: '住所・目印', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _photoUrlController,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(
              labelText: '写真のURL(任意)',
              hintText: 'https://...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text('対応排気量', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: _ccOptions
                .map((cc) => ChoiceChip(
                      label: Text(cc == 0 ? '制限なし' : '$cc cc以上可'),
                      selected: _minCc == cc,
                      onSelected: (_) => setState(() => _minCc = cc),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          Text('路面状況', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: [
              ChoiceChip(label: const Text('アスファルト'), selected: _surface == GroundSurface.asphalt, onSelected: (_) => setState(() => _surface = GroundSurface.asphalt)),
              ChoiceChip(label: const Text('砂利'), selected: _surface == GroundSurface.gravel, onSelected: (_) => setState(() => _surface = GroundSurface.gravel)),
              ChoiceChip(label: const Text('土'), selected: _surface == GroundSurface.soil, onSelected: (_) => setState(() => _surface = GroundSurface.soil)),
            ],
          ),
          const SizedBox(height: 20),
          Text('その他の条件', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _roofed,
            onChanged: (v) => setState(() => _roofed = v),
            title: const Text('屋根あり'),
            secondary: const Icon(Icons.roofing),
          ),
          SwitchListTile(
            value: _groundLockable,
            onChanged: (v) => setState(() => _groundLockable = v),
            title: const Text('地球ロック(固定物への施錠)可'),
            secondary: const Icon(Icons.lock_outline),
          ),
          SwitchListTile(
            value: _flat,
            onChanged: (v) => setState(() => _flat = v),
            title: const Text('傾斜なし'),
            secondary: const Icon(Icons.horizontal_rule),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                : const Icon(Icons.save_outlined),
            label: const Text('この内容で登録する'),
          ),
        ],
      ),
    );
  }
}
