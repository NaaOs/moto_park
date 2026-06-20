import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import '../models/parking_spot.dart';
import '../models/spot_filter.dart';
import '../services/jmpsa_dataset.dart';
import '../services/jmpsa_parking_service.dart';
import '../services/location_service.dart';
import '../services/spot_repository.dart';
import '../services/user_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/filter_sheet.dart';
import 'add_spot_screen.dart';
import 'saved_screen.dart';
import 'settings_screen.dart';
import 'spot_detail_screen.dart';

/// メイン画面: 駐輪場ピンの地図表示・絞り込み・現在地・新規登録の起点。
/// Windows では flutter_map(OpenStreetMap) を使用し、
/// Web では google_maps_flutter を使用する。
///
/// 全国JMPSAデータ(4〜5万件)を同梱しているため、地図には「表示領域内」かつ
/// 「一定ズーム以上」のマーカーのみを描画し、最大件数で打ち切ることで
/// 描画負荷を抑える(ビューポートカリング)。
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _defaultCenter = LatLng(35.681236, 139.767125);

  // 同時に描画するマーカーの上限。これを超える分は打ち切る。
  static const _maxMarkers = 50;
  // このズーム未満ではマーカーを一切描画しない(拡大したときのみピンを表示する)。
  static const _datasetMinZoom = 13.0;

  // Google Maps コントローラ (Web)
  GoogleMapController? _googleMapController;
  // flutter_map コントローラ (Windows)
  final _flutterMapController = fmap.MapController();

  final _locationService = LocationService();
  final _jmpsaService = JmpsaParkingService();
  late final JmpsaDataset _dataset; // Provider から取得する共有インスタンス

  StreamSubscription<LatLng>? _positionSub;
  LatLng? _currentLocation;
  SpotFilter _filter = const SpotFilter();
  // マイバイク排気量(設定画面で登録)。設定時は地図表示から自動で除外する。
  int? _bikeDisplacementCc;
  bool _pickingLocation = false;

  // location.php から取得する現在地周辺のライブデータ
  List<ParkingSpot> _liveSpots = [];
  bool _loadingJmpsa = false;
  LatLng? _jmpsaFetchedAround;

  // 同梱の全国データ(4〜5万件)。読み取り専用でメモリ保持する。
  List<ParkingSpot> _datasetSpots = const [];

  // 現在の表示領域とズーム。ビューポートカリングに使う。
  double _minLat = 0, _maxLat = 0, _minLng = 0, _maxLng = 0;
  double _zoom = 14;
  bool _hasViewport = false;
  Timer? _viewportDebounce;
  // 起動後、最初に現在地へカメラを合わせたかどうか。
  bool _centeredOnUser = false;

  /// Windows デスクトップでは flutter_map(OpenStreetMap) を使う(Web は Google Maps)。
  static bool get _useDesktopMap =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    _dataset = context.read<JmpsaDataset>();
    _initLocation();
    _loadDataset();
    _loadJmpsaSpots(_defaultCenter);
  }

  Future<void> _loadDataset() async {
    final spots = await _dataset.loadAll();
    if (mounted) setState(() => _datasetSpots = spots);
  }

  Future<void> _initLocation() async {
    final initial = await _locationService.getCurrentLatLng();
    if (initial != null && mounted) {
      setState(() => _currentLocation = initial);
      _maybeCenterOnUser();
      _loadJmpsaSpots(initial);
    }
    _positionSub = _locationService.watchPosition().listen((pos) {
      if (mounted) setState(() => _currentLocation = pos);
    });
  }

  void _moveCamera(LatLng target, double zoom) {
    if (_useDesktopMap) {
      _flutterMapController.move(ll.LatLng(target.latitude, target.longitude), zoom);
    } else {
      _googleMapController?.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
    }
  }

  /// 起動直後、現在地が取得でき地図も準備できていれば一度だけ現在地へ寄せる。
  /// 現在地取得とマップ生成は順序が前後しうるため、両方の契機から呼ぶ。
  void _maybeCenterOnUser() {
    if (_centeredOnUser) return;
    final loc = _currentLocation;
    if (loc == null) return;
    if (_useDesktopMap) {
      _flutterMapController.move(ll.LatLng(loc.latitude, loc.longitude), 15);
    } else {
      if (_googleMapController == null) return;
      _googleMapController!.moveCamera(CameraUpdate.newLatLngZoom(loc, 15));
    }
    _centeredOnUser = true;
  }

  Future<void> _loadJmpsaSpots(LatLng around) async {
    final last = _jmpsaFetchedAround;
    if (last != null && _distanceMeters(last, around) < 3000) return;
    if (_loadingJmpsa) return;
    setState(() => _loadingJmpsa = true);
    final spots = await _jmpsaService.fetchNearby(
      latitude: around.latitude,
      longitude: around.longitude,
    );
    if (!mounted) return;
    setState(() {
      _loadingJmpsa = false;
      _jmpsaFetchedAround = around;
      if (spots.isNotEmpty) _liveSpots = spots;
    });
  }

  double _distanceMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * (pi / 180);
    final dLng = (b.longitude - a.longitude) * (pi / 180);
    final lat1 = a.latitude * (pi / 180);
    final lat2 = b.latitude * (pi / 180);
    final s = sin(dLat / 2);
    final t = sin(dLng / 2);
    return 2 * r * asin(sqrt(s * s + cos(lat1) * cos(lat2) * t * t));
  }

  /// 表示領域の変更をまとめて反映する(パン中の過剰なsetStateを間引く)。
  void _onViewportChanged(double north, double south, double east, double west, double zoom) {
    _viewportDebounce?.cancel();
    _viewportDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        _maxLat = north;
        _minLat = south;
        _maxLng = east;
        _minLng = west;
        _zoom = zoom;
        _hasViewport = true;
      });
    });
  }

  bool _inViewport(ParkingSpot s) =>
      s.latitude >= _minLat &&
      s.latitude <= _maxLat &&
      s.longitude >= _minLng &&
      s.longitude <= _maxLng;

  /// マイバイク排気量が登録されていれば、停められない駐輪場を除外する。
  /// (spot.conditions.minDisplacementCc = その値以上の排気量が駐輪可能)
  bool _passesBike(ParkingSpot s) {
    final cc = _bikeDisplacementCc;
    if (cc == null) return true;
    return s.conditions.minDisplacementCc <= cc;
  }

  /// 描画するマーカーを決定する。
  /// 近隣データ(seed/ユーザー登録/ライブ)は常に表示し、全国同梱データは
  /// 表示領域内かつ一定ズーム以上のときに上限まで追加する。
  ({List<ParkingSpot> visible, int total}) _resolveSpots(List<ParkingSpot> repoSpots) {
    // 近隣データ(件数が少ない)をidでマージ。同梱データは後段で領域フィルタする。
    final near = <String, ParkingSpot>{};
    for (final s in repoSpots) {
      if (_filter.matches(s) && _passesBike(s)) near[s.id] = s;
    }
    for (final s in _liveSpots) {
      if (_filter.matches(s) && _passesBike(s)) near[s.id] = s;
    }
    final total = _datasetSpots.length + near.length;

    // 拡大したとき(一定ズーム以上)のみピンを表示する。
    // それ未満では地図を見やすく保つため、近隣データも含め一切描画しない。
    if (!_hasViewport || _zoom < _datasetMinZoom) {
      return (visible: const <ParkingSpot>[], total: total);
    }

    final visible = <ParkingSpot>[];
    // 近隣データ(seed/ユーザー登録/ライブ)を優先して表示。
    for (final s in near.values) {
      if (visible.length >= _maxMarkers) break;
      if (_inViewport(s)) visible.add(s);
    }
    // 全国同梱データを上限まで追加。
    for (final s in _datasetSpots) {
      if (visible.length >= _maxMarkers) break;
      if (near.containsKey(s.id)) continue;
      if (!_inViewport(s)) continue;
      if (!_filter.matches(s) || !_passesBike(s)) continue;
      visible.add(s);
    }
    return (visible: visible, total: total);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _viewportDebounce?.cancel();
    _flutterMapController.dispose();
    super.dispose();
  }

  Future<void> _openFilter() async {
    final result = await FilterSheet.show(context, _filter);
    if (result != null) setState(() => _filter = result);
  }

  void _focusOnMyLocation() {
    final loc = _currentLocation;
    if (loc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在地を取得中です…')),
      );
      return;
    }
    _moveCamera(loc, 16);
    _loadJmpsaSpots(loc);
  }

  Future<void> _onMapLongPress(LatLng point) async {
    if (_pickingLocation) return;
    setState(() => _pickingLocation = true);
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => AddSpotScreen(initialLocation: point)),
      );
    } finally {
      if (mounted) setState(() => _pickingLocation = false);
    }
  }

  void _openDetail(ParkingSpot spot) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: spot)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // マイバイク排気量を反映(設定変更で自動的に再描画される)。
    _bikeDisplacementCc = context.watch<UserPreferences>().bikeDisplacementCc;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MotoPark'),
        actions: [
          IconButton(
            tooltip: '保存した駐輪場',
            icon: const Icon(Icons.favorite_border),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SavedScreen()),
            ),
          ),
          IconButton(
            tooltip: '設定',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<ParkingSpot>>(
        stream: context.read<SpotRepository>().watchActiveSpots(),
        builder: (context, snapshot) {
          final repoSpots = snapshot.data ?? const <ParkingSpot>[];
          final resolved = _resolveSpots(repoSpots);
          final spots = resolved.visible;

          final tooFarOut = _hasViewport &&
              _zoom < _datasetMinZoom &&
              _datasetSpots.isNotEmpty;

          return Stack(
            children: [
              // 地図は画面全体に表示し、操作UIだけ SafeArea 内に収める(ノッチ対応)。
              _useDesktopMap ? _buildFlutterMap(spots) : _buildGoogleMap(spots),
              Positioned.fill(
                child: SafeArea(
                  minimum: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 8,
                        child: _TopBar(
                          visibleCount: spots.length,
                          totalCount: resolved.total,
                          filterActive: _filter.isActive,
                          filterCount: _filter.activeCount,
                          onTapFilter: _openFilter,
                        ),
                      ),
                      if (tooFarOut)
                        const Positioned(
                          top: 70,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _HintPill(text: '地図を拡大すると駐輪場が表示されます'),
                          ),
                        ),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Positioned(
                          bottom: 110,
                          left: 0,
                          right: 0,
                          child: Center(child: _LoadingPill(text: '駐輪場情報を読み込み中…')),
                        ),
                      if (_loadingJmpsa)
                        const Positioned(
                          bottom: 110,
                          left: 0,
                          right: 0,
                          child: Center(child: _LoadingPill(text: 'JMPSAから最新情報を取得中…')),
                        ),
                      Positioned(
                        bottom: 16,
                        right: 8,
                        child: _BigFab(
                          icon: Icons.my_location,
                          tooltip: '現在地',
                          onPressed: _focusOnMyLocation,
                        ),
                      ),
                      // 出典表示。FAB(右下)と重ならないよう右側に余白を確保し、
                      // 狭い画面では省略表示にする。
                      const Positioned(
                        left: 8,
                        right: 92,
                        bottom: 16,
                        child: _HintPill(text: '出典: JMPSA(日本二輪車普及安全協会)'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Google Maps (Web) ─────────────────────────────────────────────────────

  Widget _buildGoogleMap(List<ParkingSpot> spots) {
    return GoogleMap(
      initialCameraPosition: const CameraPosition(target: _defaultCenter, zoom: 14),
      onMapCreated: (c) {
        _googleMapController = c;
        _updateGoogleViewport();
        _maybeCenterOnUser();
      },
      onCameraMove: (pos) => _zoom = pos.zoom,
      onCameraIdle: _updateGoogleViewport,
      onLongPress: _onMapLongPress,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      // 標準のズームボタン・方向(コンパス)ボタン・ツールバーを非表示にする。
      zoomControlsEnabled: false,
      compassEnabled: false,
      rotateGesturesEnabled: false,
      mapToolbarEnabled: false,
      markers: spots
          .map((spot) => Marker(
                markerId: MarkerId(spot.id),
                position: LatLng(spot.latitude, spot.longitude),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  spot.official ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueViolet,
                ),
                infoWindow: InfoWindow(title: spot.name, snippet: spot.feeDescription),
                onTap: () => _openDetail(spot),
              ))
          .toSet(),
    );
  }

  Future<void> _updateGoogleViewport() async {
    final controller = _googleMapController;
    if (controller == null) return;
    final region = await controller.getVisibleRegion();
    final ne = region.northeast;
    final sw = region.southwest;
    _onViewportChanged(ne.latitude, sw.latitude, ne.longitude, sw.longitude, _zoom);
  }

  // ── flutter_map / OpenStreetMap (Windows) ─────────────────────────────────

  Widget _buildFlutterMap(List<ParkingSpot> spots) {
    return fmap.FlutterMap(
      mapController: _flutterMapController,
      options: fmap.MapOptions(
        initialCenter: ll.LatLng(_defaultCenter.latitude, _defaultCenter.longitude),
        initialZoom: 14,
        onMapReady: () {
          _updateFlutterViewport();
          _maybeCenterOnUser();
        },
        onPositionChanged: (camera, hasGesture) {
          final b = camera.visibleBounds;
          _onViewportChanged(b.north, b.south, b.east, b.west, camera.zoom);
        },
        onLongPress: (_, point) =>
            _onMapLongPress(LatLng(point.latitude, point.longitude)),
      ),
      children: [
        fmap.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'jp.or.jmpsa.motopark',
        ),
        fmap.MarkerLayer(
          markers: spots.map((spot) {
            final color = spot.official ? AppTheme.accent : Colors.purple;
            return fmap.Marker(
              point: ll.LatLng(spot.latitude, spot.longitude),
              width: 40,
              height: 40,
              child: GestureDetector(
                onTap: () => _openDetail(spot),
                child: Icon(Icons.location_pin, color: color, size: 40),
              ),
            );
          }).toList(),
        ),
        const fmap.SimpleAttributionWidget(
          source: Text('© OpenStreetMap contributors'),
        ),
      ],
    );
  }

  void _updateFlutterViewport() {
    final b = _flutterMapController.camera.visibleBounds;
    _onViewportChanged(b.north, b.south, b.east, b.west, _flutterMapController.camera.zoom);
  }
}

class _BigFab extends StatelessWidget {
  const _BigFab({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppTheme.surface,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 64,
            height: 64,
            child: Icon(icon, size: 30, color: AppTheme.accent),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.visibleCount,
    required this.totalCount,
    required this.filterActive,
    required this.filterCount,
    required this.onTapFilter,
  });

  final int visibleCount;
  final int totalCount;
  final bool filterActive;
  final int filterCount;
  final VoidCallback onTapFilter;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(16),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTapFilter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.tune, color: filterActive ? AppTheme.accent : Colors.black54, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  filterActive
                      ? '絞り込み中 ($filterCount件) · 表示 $visibleCount 件'
                      : '全国 $totalCount 件 · 表示中 $visibleCount 件 · タップで絞り込み',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingPill extends StatelessWidget {
  const _LoadingPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(text),
        ],
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: Colors.black54),
      ),
    );
  }
}
