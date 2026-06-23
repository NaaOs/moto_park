import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/parking_spot.dart';
import '../models/spot_report.dart';
import '../services/jmpsa_parking_service.dart';
import '../services/navigation_launcher.dart';
import '../services/spot_repository.dart';
import '../services/user_preferences.dart';
import '../theme/app_theme.dart';
import 'update_request_screen.dart';

/// 駐輪場の詳細画面。
/// 料金・対応条件・経路案内連携・進入路ストリートビュー・通報をここに集約する。
///
/// JMPSA由来のスポットは、開いたときに詳細ページを遅延取得して
/// 備考(予約案内・予約URL)と写真を追加表示する。
class SpotDetailScreen extends StatefulWidget {
  const SpotDetailScreen({super.key, required this.spot});

  final ParkingSpot spot;

  @override
  State<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends State<SpotDetailScreen> {
  final _jmpsaService = JmpsaParkingService();
  JmpsaSpotDetail? _detail;
  bool _loadingDetail = false;

  ParkingSpot get spot => widget.spot;

  @override
  void initState() {
    super.initState();
    // 同梱データに詳細が焼き込まれていれば即座に表示(オフラインでも見られる)。
    if (spot.hasDetails) _detail = JmpsaSpotDetail.fromSpot(spot);
    // 写真や最新情報を詳細ページから遅延取得して上書きする。
    _loadDetailIfJmpsa();
    // 「最近見た」に記録する(build後にProvider更新するためマイクロタスクで)。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<UserPreferences>().addRecent(spot.id);
    });
  }

  /// 共有用テキスト(名称・住所・Googleマップのリンク)を作る。
  String _shareText() {
    final mapUrl = 'https://www.google.com/maps/search/?api=1&query=${spot.latitude},${spot.longitude}';
    final addr = spot.address.isEmpty ? '' : '\n${spot.address}';
    return '${spot.name}$addr\n$mapUrl';
  }

  Future<void> _share() async {
    final text = _shareText();
    try {
      await Share.share(text, subject: spot.name);
    } catch (_) {
      // 共有が使えない環境(一部デスクトップ等)ではクリップボードにコピー。
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('共有情報をクリップボードにコピーしました')),
        );
      }
    }
  }

  Future<void> _loadDetailIfJmpsa() async {
    final url = spot.infoUrl;
    if (spot.createdBy != 'jmpsa' || url == null) return;
    setState(() => _loadingDetail = true);
    final detail = await _jmpsaService.fetchDetail(url);
    if (!mounted) return;
    setState(() {
      _loadingDetail = false;
      // 取得できたときだけ上書きする(失敗時は焼き込み済みの詳細を残す)。
      if (detail != null) _detail = detail;
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<SpotRepository>();
    final photos = spot.photoUrls.isNotEmpty
        ? spot.photoUrls
        : (_detail?.photoUrls ?? const <String>[]);

    final prefs = context.watch<UserPreferences>();
    final isFav = prefs.isFavorite(spot.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(spot.name),
        actions: [
          IconButton(
            tooltip: isFav ? 'お気に入りから削除' : 'お気に入りに追加',
            icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                color: isFav ? Colors.redAccent : null),
            onPressed: () => prefs.toggleFavorite(spot.id),
          ),
          IconButton(
            tooltip: '共有',
            icon: const Icon(Icons.share),
            onPressed: _share,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeroMedia(photos),
          const SizedBox(height: 16),
          _FeeCard(spot: spot),
          const SizedBox(height: 16),
          _InfoCard(spot: spot),
          if (_detail != null) ...[
            const SizedBox(height: 16),
            _JmpsaDetailCard(detail: _detail!),
          ],
          if (_detail != null && _detail!.remarks.isNotEmpty) ...[
            const SizedBox(height: 16),
            _RemarksCard(
              remarks: _detail!.remarks,
              reservationUrl: _detail!.reservationUrl,
            ),
          ],
          const SizedBox(height: 16),
          if (spot.streetViewUrl != null) _StreetViewCard(url: spot.streetViewUrl!),
          if (spot.infoUrl != null) ...[
            const SizedBox(height: 16),
            _ReferenceCard(url: spot.infoUrl!),
          ],
          const SizedBox(height: 16),
          // 掲載情報の更新・削除依頼ページへ遷移する。
          Card(
            child: ListTile(
              leading: const Icon(Icons.edit_note, size: 30, color: AppTheme.accent),
              title: const Text('掲載情報の更新・削除依頼'),
              subtitle: const Text('閉鎖・内容変更などの依頼方法をご案内します'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => UpdateRequestScreen(spot: spot)),
              ),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () => NavigationLauncher().launchTo(
              latitude: spot.latitude,
              longitude: spot.longitude,
              label: spot.name,
            ),
            icon: const Icon(Icons.navigation),
            label: const Text('ここへナビ開始'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
            ),
            onPressed: () => _showReportDialog(context, repo),
            icon: const Icon(Icons.flag_outlined),
            label: const Text('情報の誤りを報告する'),
          ),
          const SizedBox(height: 24),
          // 最下部のバナー(加工せずそのまま表示)。
          Center(child: Image.asset('assets/banner.png')),
        ],
      ),
    );
  }

  /// 画像エリア。写真があればカルーセル、取得中はローディング、
  /// 写真が無ければ地図プレビューを表示する。
  Widget _buildHeroMedia(List<String> photos) {
    if (photos.isNotEmpty) {
      return SizedBox(
        height: 180,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: photos.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              photos[i],
              width: 240,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _photoPlaceholder(),
            ),
          ),
        ),
      );
    }
    // 取得完了までは確定させず、ローディングを表示(ちらつき防止)。
    if (_loadingDetail) return _loadingMedia();
    // 写真が無い場合は、場所が分かる地図プレビューを代わりに表示。
    return _mapPreview();
  }

  /// 写真取得中のローディング表示。
  Widget _loadingMedia() {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(height: 10),
          Text('写真を確認中…', style: TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  /// 写真が無いときの代替: 駐輪場の位置を示す操作不可の地図プレビュー(OSM・キー不要)。
  Widget _mapPreview() {
    final point = ll.LatLng(spot.latitude, spot.longitude);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 160,
        child: Stack(
          children: [
            fmap.FlutterMap(
              options: fmap.MapOptions(
                initialCenter: point,
                initialZoom: 16,
                interactionOptions: const fmap.InteractionOptions(flags: fmap.InteractiveFlag.none),
              ),
              children: [
                fmap.TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'jp.or.jmpsa.motopark',
                ),
                fmap.MarkerLayer(
                  markers: [
                    fmap.Marker(
                      point: point,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_pin, color: AppTheme.accent, size: 40),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_outlined, size: 14, color: Colors.white),
                    SizedBox(width: 5),
                    Text('写真なし — 地図で表示', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const Positioned(
              right: 4,
              bottom: 2,
              child: Text(
                '© OpenStreetMap',
                style: TextStyle(fontSize: 9, color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder({double height = 180}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.photo_camera_outlined, size: 48, color: Colors.black26),
    );
  }

  Future<void> _showReportDialog(BuildContext context, SpotRepository repo) async {
    final reason = await showDialog<ReportReason>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('通報理由を選択'),
        children: ReportReason.values
            .map((r) => SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(reportReasonLabel(r), style: const TextStyle(fontSize: 16)),
                  ),
                ))
            .toList(),
      ),
    );
    if (reason == null || !context.mounted) return;
    await repo.reportSpot(spotId: spot.id, reason: reason);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('通報を受け付けました。ご協力ありがとうございます。')),
      );
    }
  }
}

/// JMPSA詳細ページの項目(バイク種別・車両制限・収容台数・利用可能時間)を表示するカード。
/// 値が取得できた項目のみ表示し、何も無ければ表示しない。
class _JmpsaDetailCard extends StatelessWidget {
  const _JmpsaDetailCard({required this.detail});

  final JmpsaSpotDetail detail;

  @override
  Widget build(BuildContext context) {
    final rows = <({IconData icon, String label, String? value})>[
      (icon: Icons.two_wheeler, label: 'バイク種別', value: detail.bikeType),
      (icon: Icons.do_not_disturb_on_outlined, label: '車両制限', value: detail.vehicleRestriction),
      (icon: Icons.local_parking, label: '駐車場形態', value: detail.parkingType),
      (icon: Icons.schedule, label: '利用可能時間', value: detail.availableHours),
      (icon: Icons.confirmation_number_outlined, label: '収容台数', value: detail.capacity),
      (icon: Icons.call_outlined, label: 'TEL', value: detail.tel),
      (icon: Icons.business_outlined, label: '管理会社', value: detail.managementCompany),
      (icon: Icons.update_outlined, label: '最終更新日', value: detail.lastUpdated),
    ].where((r) => r.value != null && r.value!.isNotEmpty).toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(rows[i].icon, size: 20, color: Colors.black54),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 88,
                    child: Text(
                      rows[i].label,
                      style: const TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rows[i].value!,
                      style: const TextStyle(fontSize: 15, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 備考カード。予約制の場合は備考文に加えて予約サイトへのボタンを表示する。
class _RemarksCard extends StatelessWidget {
  const _RemarksCard({required this.remarks, this.reservationUrl});

  final String remarks;
  final String? reservationUrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sticky_note_2_outlined, size: 20, color: Colors.black54),
                const SizedBox(width: 8),
                const Text('備考', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 8),
            Text(remarks, style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4)),
            if (reservationUrl != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppTheme.accent,
                ),
                onPressed: () =>
                    launchUrl(Uri.parse(reservationUrl!), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.event_available),
                label: const Text('予約サイトを開く'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeeCard extends StatelessWidget {
  const _FeeCard({required this.spot});
  final ParkingSpot spot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.1),
        border: Border.all(color: AppTheme.accent),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_outlined, color: AppTheme.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  spot.feeDescription.isEmpty ? '時間貸し駐輪場(料金詳細は現地表示をご確認ください)' : spot.feeDescription,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                ),
              ),
            ],
          ),
          if (spot.closedDays.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.event_busy_outlined, color: AppTheme.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '定休日: ${spot.closedDays}',
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.spot});
  final ParkingSpot spot;

  @override
  Widget build(BuildContext context) {
    final c = spot.conditions;
    // 排気量タグは同梱データ(バイク種別/車両制限から導出済みの範囲)で判定する。
    final tags = <String>[
      c.displacementText,
      if (c.roofed) '屋根あり',
      if (c.groundLockable) '地球ロック可',
      if (c.flat) '傾斜なし',
      if (c.surface != GroundSurface.unknown) _surfaceLabel(c.surface),
      spot.official ? '公式情報' : 'ユーザー投稿',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 20, color: Colors.black54),
                const SizedBox(width: 8),
                Expanded(child: Text(spot.address, style: const TextStyle(color: Colors.black87))),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tags.map((t) => Chip(label: Text(t))).toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _surfaceLabel(GroundSurface s) {
    switch (s) {
      case GroundSurface.asphalt:
        return '路面: アスファルト';
      case GroundSurface.gravel:
        return '路面: 砂利';
      case GroundSurface.soil:
        return '路面: 土';
      case GroundSurface.unknown:
        return '路面: 不明';
    }
  }
}

class _StreetViewCard extends StatelessWidget {
  const _StreetViewCard({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.streetview, size: 30, color: AppTheme.accent),
        title: const Text('進入路をストリートビューで確認'),
        subtitle: const Text('段差や切り返しスペースを事前にチェックできます'),
        trailing: const Icon(Icons.open_in_new),
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ),
    );
  }
}

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.fact_check_outlined, size: 30, color: AppTheme.accent),
        title: const Text('JMPSAで最新の駐車場情報を確認'),
        subtitle: const Text('料金・営業時間は現状と異なる場合があります'),
        trailing: const Icon(Icons.open_in_new),
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ),
    );
  }
}
