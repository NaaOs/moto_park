import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/parking_spot.dart';

/// Web判定(Flutter非依存)。flutter/foundation の kIsWeb を import すると
/// dart:ui を引き込み、tool/ の harvest スクリプトを純粋な `dart run` で
/// 実行できなくなるため、Flutterと同じ定義を自前で持つ。
/// ライブラリ非公開にして、利用側(map_screen 等)の flutter 由来 kIsWeb と衝突させない。
const bool _kIsWeb = bool.fromEnvironment('dart.library.js_util');

/// 駐車場詳細ページから追加取得する情報。
/// 予約先URL・備考・写真に加え、詳細テーブルの各項目(収容台数・車両制限など)を保持する。
class JmpsaSpotDetail {
  final String remarks; // 備考(予約案内文など)
  final String? reservationUrl; // 予約サービス(akippa/特P等)のURL
  final List<String> photoUrls; // 駐車場の写真
  // 詳細テーブルの項目(ラベル→値)。例: {'収容台数':'30台','車両制限':'排気量50cc以下は不可', ...}
  final Map<String, String> info;

  const JmpsaSpotDetail({
    this.remarks = '',
    this.reservationUrl,
    this.photoUrls = const [],
    this.info = const {},
  });

  /// 同梱データ(harvest時に焼き込んだ ParkingSpot.details)から詳細を組み立てる。
  /// 写真は遅延取得でのみ得られるため空にする(必要時にネットワークから上書きする)。
  factory JmpsaSpotDetail.fromSpot(ParkingSpot spot) => JmpsaSpotDetail(
        remarks: spot.remarks,
        reservationUrl: spot.reservationUrl,
        info: spot.details,
      );

  String? get bikeType => info['バイク種別']; // 対応するバイクのサイズ区分(50cc以下 等)
  String? get parkingType => info['駐車場形態']; // 種別(時間貸 等)
  String? get availableHours => info['利用可能時間'];
  String? get capacity => info['収容台数'];
  String? get vehicleRestriction => info['車両制限'];
  String? get tel => info['TEL'];
  String? get hourlyFee => info['料金（時間貸）'];
  String? get managementCompany => info['管理会社'];
  String? get lastUpdated => info['最終更新日'];

  bool get isEmpty =>
      remarks.isEmpty && reservationUrl == null && photoUrls.isEmpty && info.isEmpty;
}

/// 提携データ提供元の駐車場検索(https://www.jmpsa.or.jp/society/parking/)から
/// 現在地周辺の時間貸し駐輪場を動的に取得するサービス。
///
/// 提携データの「現在地から検索」機能と同じエンドポイント(location.php)を利用し、
/// 返却されるHTMLから施設名・住所・緯度経度・料金・定休日を抽出する。
class JmpsaParkingService {
  static const _baseUrl = 'https://www.jmpsa.or.jp';

  // Web公開時のCORS回避用プロキシ(Cloudflare Worker)のベースURL。
  // ビルド時に --dart-define=JMPSA_PROXY=https://...workers.dev で注入する。
  // 空の場合(デスクトップ/モバイル/開発)は直接アクセスする。
  static const _proxyBase = String.fromEnvironment('JMPSA_PROXY');

  // 時間貸し(types=1)のみを対象とする。
  static const _typesHourly = '1';

  /// Web かつプロキシ設定済みのときだけ、データ提供元へのリクエストをプロキシ経由にする。
  /// 画像表示(Image.network)はブラウザの<img>で直接読めるため対象外。
  static String _proxied(String url) {
    if (!_kIsWeb || _proxyBase.isEmpty) return url;
    if (url.startsWith(_baseUrl)) return '$_proxyBase${url.substring(_baseUrl.length)}';
    return url;
  }

  static final _itemPattern = RegExp(
    r'<li class="p-parking-prefecture-list-item">(.*?)</li>',
    dotAll: true,
  );
  static final _latLngPattern = RegExp(r'[?&]q=(-?[\d.]+),(-?[\d.]+)&zoom=');
  static final _nameLinkPattern = RegExp(
    r'<a href="([^"]+)" class="m-c-link">(.*?)<span',
    dotAll: true,
  );
  static final _addressPattern = RegExp(
    r'p-parking-prefecture-map-txt">(.*?)</p>',
    dotAll: true,
  );
  static final _tablePattern = RegExp(
    r'p-parking-prefecture-table-ttl">(.*?)</p>\s*<p class="p-parking-prefecture-table-txt">(.*?)</p>',
    dotAll: true,
  );
  static final _idPattern = RegExp(r'/p-(\w+)\.html');

  // 詳細ページのテーブル行(項目名→値)。所在地・収容台数・車両制限・備考 等。
  static final _detailRowPattern = RegExp(
    r'detail-table-ttl">(.*?)</th>\s*<td class="p-parking-detail-table-txt"[^>]*>(.*?)</td>',
    dotAll: true,
  );
  // 詳細ページ内の予約サービス等の外部URL。
  static final _hrefPattern = RegExp(r'href="(https?://[^"]+)"');
  // 駐車場写真(/prg_img/img/xxx.jpg)。
  static final _photoPattern = RegExp(r'/prg_img/img/[^"' "'" r']+\.(?:jpg|jpeg|png)', caseSensitive: false);

  /// 指定した緯度経度の周辺にある時間貸し駐輪場をデータ提供元から取得する。
  /// 通信失敗・解析失敗時は空リストを返す(オフライン時はローカルデータのみ表示)。
  Future<List<ParkingSpot>> fetchNearby({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse('$_baseUrl/society/parking/location.php').replace(queryParameters: {
      'lat': latitude.toString(),
      'lng': longitude.toString(),
      'types': _typesHourly,
    });

    try {
      final response = await http
          .get(Uri.parse(_proxied(uri.toString())),
              headers: const {'User-Agent': 'Mozilla/5.0 (MotoParkApp)'})
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return const [];
      // Content-Type が不正(末尾;)なエンドポイント対策で bodyBytes を直接デコードする。
      return parseHtml(utf8.decode(response.bodyBytes, allowMalformed: true));
    } catch (_) {
      return const [];
    }
  }

  /// 駐車場の詳細ページ(infoUrl)から備考・予約URL・写真を取得する。
  /// 詳細画面を開いたときに遅延取得する用途。失敗時は null を返す。
  Future<JmpsaSpotDetail?> fetchDetail(String url) async {
    final uri = Uri.tryParse(_proxied(url));
    if (uri == null) return null;
    try {
      final response = await http
          .get(uri, headers: const {'User-Agent': 'Mozilla/5.0 (MotoParkApp)'})
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      return parseDetail(utf8.decode(response.bodyBytes, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  /// 詳細ページHTMLから備考・予約URL・写真・各項目を抽出する(テストのため公開)。
  JmpsaSpotDetail parseDetail(String html) {
    var remarks = '';
    String? reservationUrl;
    final info = <String, String>{};

    // 詳細テーブルの各行を項目名→値で取り込む。
    for (final m in _detailRowPattern.allMatches(html)) {
      final label = _clean(m.group(1)!);
      final rawValue = m.group(2)!;
      if (label.isEmpty) continue;
      if (label == '備考') {
        remarks = _cleanMultiline(rawValue);
        final href = _hrefPattern.firstMatch(rawValue);
        if (href != null) reservationUrl = _decodeEntities(href.group(1)!);
      } else {
        // TEL等はリンク(<a href="tel:...">番号</a>)で囲まれているため、
        // アンカーは残してテキストだけ取り出す(備考のみリンクを除去する)。
        final value = _cleanKeepText(rawValue);
        if (value.isNotEmpty) info[label] = value;
      }
    }

    // 写真URLを重複排除しつつ絶対URL化する。
    // Web(CanvasKit)はクロスオリジン画像にもCORSが必要なため、Web時はプロキシ経由にする。
    final photos = <String>[];
    for (final m in _photoPattern.allMatches(html)) {
      final abs = _proxied('$_baseUrl${m.group(0)}');
      if (!photos.contains(abs)) photos.add(abs);
    }

    return JmpsaSpotDetail(
      remarks: remarks,
      reservationUrl: reservationUrl,
      photoUrls: photos,
      info: info,
    );
  }

  /// location.php/area*.htmlのレスポンスHTMLから駐車場一覧を抽出する。
  /// テストや解析確認のため公開メソッドとしている。
  List<ParkingSpot> parseHtml(String html) {
    final spots = <ParkingSpot>[];
    for (final item in _itemPattern.allMatches(html)) {
      final block = item.group(1)!;

      final latLng = _latLngPattern.firstMatch(block);
      final nameLink = _nameLinkPattern.firstMatch(block);
      if (latLng == null || nameLink == null) continue;

      final latitude = double.tryParse(latLng.group(1)!);
      final longitude = double.tryParse(latLng.group(2)!);
      if (latitude == null || longitude == null) continue;

      final detailPath = nameLink.group(1)!;
      final name = _clean(nameLink.group(2)!);
      if (name.isEmpty) continue;

      final addressMatch = _addressPattern.firstMatch(block);
      final address = addressMatch == null ? '' : _clean(addressMatch.group(1)!);

      var closedDays = '';
      var fee = '';
      for (final table in _tablePattern.allMatches(block)) {
        final label = _clean(table.group(1)!);
        final value = _clean(table.group(2)!);
        if (label == '定休日') {
          closedDays = value;
        } else if (label == '料金') {
          fee = value;
        }
      }

      final idMatch = _idPattern.firstMatch(detailPath);
      final id = idMatch == null ? 'jmpsa-${spots.length}-$latitude-$longitude' : 'jmpsa-${idMatch.group(1)}';

      spots.add(ParkingSpot(
        id: id,
        name: name,
        address: address,
        latitude: latitude,
        longitude: longitude,
        official: true,
        pricingType: PricingType.hourly,
        feeDescription: fee,
        closedDays: closedDays,
        infoUrl: detailPath.startsWith('http') ? detailPath : '$_baseUrl$detailPath',
        createdBy: 'jmpsa',
      ));
    }
    return spots;
  }

  String _clean(String text) {
    return _decodeEntities(text.replaceAll(RegExp(r'<[^>]*>'), '')).trim();
  }

  /// <br>を改行に変換しつつタグを除去する(備考など複数行テキスト向け)。
  /// 予約URLは別途ボタンで表示するため、アンカー要素は本文から取り除く。
  String _cleanMultiline(String text) {
    final withoutAnchors =
        text.replaceAll(RegExp(r'<a\b[^>]*>.*?</a>', dotAll: true, caseSensitive: false), '');
    final withBreaks =
        withoutAnchors.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    return _decodeEntities(withBreaks.replaceAll(RegExp(r'<[^>]*>'), ''))
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
  }

  /// <br>を改行に変換しつつタグを除去する。アンカー(<a>)の中身は残す。
  /// TEL等、値がリンクで囲まれている項目向け。
  String _cleanKeepText(String text) {
    final withBreaks =
        text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    return _decodeEntities(withBreaks.replaceAll(RegExp(r'<[^>]*>'), ''))
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
  }

  String _decodeEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&nbsp;', ' ');
  }
}
