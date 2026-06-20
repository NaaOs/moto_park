import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/parking_spot.dart';

/// JMPSAの駐車場詳細ページから追加取得する情報。
/// 予約制の場合の予約先URL・備考・写真など、一覧には無い項目を保持する。
class JmpsaSpotDetail {
  final String remarks; // 備考(予約案内文など)
  final String? reservationUrl; // 予約サービス(akippa/特P等)のURL
  final List<String> photoUrls; // 駐車場の写真

  const JmpsaSpotDetail({
    this.remarks = '',
    this.reservationUrl,
    this.photoUrls = const [],
  });

  bool get isEmpty => remarks.isEmpty && reservationUrl == null && photoUrls.isEmpty;
}

/// JMPSA(日本二輪車普及安全協会)の駐車場検索(https://www.jmpsa.or.jp/society/parking/)から
/// 現在地周辺の時間貸し駐輪場を動的に取得するサービス。
///
/// JMPSAの「現在地から検索」機能と同じエンドポイント(location.php)を利用し、
/// 返却されるHTMLから施設名・住所・緯度経度・料金・定休日を抽出する。
class JmpsaParkingService {
  static const _baseUrl = 'https://www.jmpsa.or.jp';

  // 時間貸し(types=1)のみを対象とする。
  static const _typesHourly = '1';

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

  // 詳細ページの「備考」行(予約案内文・予約URLを含む)。
  static final _remarksPattern = RegExp(
    r'detail-table-ttl">備考</th>\s*<td class="p-parking-detail-table-txt"[^>]*>(.*?)</td>',
    dotAll: true,
  );
  // 詳細ページ内の予約サービス等の外部URL。
  static final _hrefPattern = RegExp(r'href="(https?://[^"]+)"');
  // 駐車場写真(/prg_img/img/xxx.jpg)。
  static final _photoPattern = RegExp(r'/prg_img/img/[^"' "'" r']+\.(?:jpg|jpeg|png)', caseSensitive: false);

  /// 指定した緯度経度の周辺にある時間貸し駐輪場をJMPSAから取得する。
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
          .get(uri, headers: const {'User-Agent': 'Mozilla/5.0 (MotoParkApp)'})
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
    final uri = Uri.tryParse(url);
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

  /// 詳細ページHTMLから備考・予約URL・写真を抽出する(テストのため公開)。
  JmpsaSpotDetail parseDetail(String html) {
    var remarks = '';
    String? reservationUrl;
    final remarksMatch = _remarksPattern.firstMatch(html);
    if (remarksMatch != null) {
      final inner = remarksMatch.group(1)!;
      remarks = _cleanMultiline(inner);
      final href = _hrefPattern.firstMatch(inner);
      if (href != null) reservationUrl = _decodeEntities(href.group(1)!);
    }

    // 写真URLを重複排除しつつ絶対URL化する。
    final photos = <String>[];
    for (final m in _photoPattern.allMatches(html)) {
      final abs = '$_baseUrl${m.group(0)}';
      if (!photos.contains(abs)) photos.add(abs);
    }

    return JmpsaSpotDetail(
      remarks: remarks,
      reservationUrl: reservationUrl,
      photoUrls: photos,
    );
  }

  /// JMPSAのlocation.php/area*.htmlのレスポンスHTMLから駐車場一覧を抽出する。
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
