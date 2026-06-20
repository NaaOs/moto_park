import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/parking_spot.dart';
import '../services/jmpsa_dataset.dart';
import '../services/spot_repository.dart';
import '../services/user_preferences.dart';
import 'spot_detail_screen.dart';

/// お気に入り・最近見た駐輪場の一覧画面。
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  // IDからスポットを引くための索引(同梱データ + ユーザー登録分)。
  Map<String, ParkingSpot>? _index;

  @override
  void initState() {
    super.initState();
    _buildIndex();
  }

  Future<void> _buildIndex() async {
    final datasetService = context.read<JmpsaDataset>();
    final repo = context.read<SpotRepository>();
    final dataset = await datasetService.loadAll();
    final repoSpots = await repo.snapshot();
    if (!mounted) return;
    final map = <String, ParkingSpot>{};
    for (final s in dataset) {
      map[s.id] = s;
    }
    for (final s in repoSpots) {
      map[s.id] = s;
    }
    setState(() => _index = map);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UserPreferences>();
    final index = _index;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('保存した駐輪場'),
          bottom: const TabBar(
            tabs: [Tab(text: 'お気に入り'), Tab(text: '最近見た')],
          ),
        ),
        body: index == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _SpotList(
                    ids: prefs.favorites,
                    index: index,
                    emptyText: 'お気に入りはまだありません。\n詳細画面の♡で追加できます。',
                  ),
                  _SpotList(
                    ids: prefs.recent,
                    index: index,
                    emptyText: '最近見た駐輪場はまだありません。',
                  ),
                ],
              ),
      ),
    );
  }
}

class _SpotList extends StatelessWidget {
  const _SpotList({required this.ids, required this.index, required this.emptyText});

  final List<String> ids;
  final Map<String, ParkingSpot> index;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (final id in ids)
        if (index[id] != null) index[id]!,
    ];
    if (spots.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, height: 1.5),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: spots.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final spot = spots[i];
        return ListTile(
          leading: Icon(
            Icons.local_parking,
            color: spot.requiresReservation ? Colors.deepPurple : Colors.teal,
          ),
          title: Text(spot.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(spot.address, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
          ),
        );
      },
    );
  }
}
