// assets/jmpsa_spots.json の各スポットに「駐輪可能な排気量範囲」を付与する。
//
// 予約制スポットは排気量制限なし(サンプル調査で確認済み)のため詳細取得をスキップし、
// 一般スポット(約3,000件)のみ詳細ページから「バイク種別/車両制限」を取得して
// conditions.minDisplacementCc / maxDisplacementCc を設定する。
//
// 実行: moto_park ディレクトリで
//   dart run tool/enrich_displacement.dart
//
// ※ flutter 非依存(http直叩き+インライン解析)。サービス層はflutterに依存するため
//   ここでは import せず、排気量導出のみ model の deriveDisplacementRange を使う。
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:motopark/models/parking_spot.dart';

const _concurrency = 8;
const _userAgent = 'Mozilla/5.0 (MotoParkEnrich)';

final _rowPattern = RegExp(
  r'detail-table-ttl">(.*?)</th>\s*<td class="p-parking-detail-table-txt"[^>]*>(.*?)</td>',
  dotAll: true,
);

String _clean(String s) => s
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&nbsp;', ' ')
    .trim();

/// 詳細ページHTMLから「バイク種別」「車両制限」を取り出す。
({String? bikeType, String? vehicleRestriction}) _parse(String html) {
  String? bikeType;
  String? vehicleRestriction;
  for (final m in _rowPattern.allMatches(html)) {
    final label = _clean(m.group(1)!);
    final value = _clean(m.group(2)!);
    if (label == 'バイク種別') {
      bikeType = value;
    } else if (label == '車両制限') {
      vehicleRestriction = value;
    }
  }
  return (bikeType: bikeType, vehicleRestriction: vehicleRestriction);
}

Future<String?> _get(String url) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final r = await http
          .get(Uri.parse(url), headers: const {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) return utf8.decode(r.bodyBytes, allowMalformed: true);
      if (r.statusCode == 404) return null;
    } catch (_) {
      // リトライ
    }
    await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
  }
  return null;
}

Future<void> main() async {
  final file = File('assets/jmpsa_spots.json');
  final list =
      (jsonDecode(await file.readAsString()) as List).cast<Map<String, dynamic>>();
  final sw = Stopwatch()..start();

  final targets = <int>[];
  for (var i = 0; i < list.length; i++) {
    final name = list[i]['name'] as String? ?? '';
    if (!name.contains('予約制') && list[i]['infoUrl'] is String) targets.add(i);
  }
  stdout.writeln('対象(一般)=${targets.length} / 全${list.length}件');
  await stdout.flush();

  var processed = 0;
  var restricted = 0;

  for (var start = 0; start < targets.length; start += _concurrency) {
    final batch = targets.skip(start).take(_concurrency).toList();
    await Future.wait(batch.map((i) async {
      final html = await _get(list[i]['infoUrl'] as String);
      if (html == null) return;
      final parsed = _parse(html);
      final r = deriveDisplacementRange(
        bikeType: parsed.bikeType,
        vehicleRestriction: parsed.vehicleRestriction,
      );
      final cond =
          ((list[i]['conditions'] as Map?) ?? {}).cast<String, dynamic>();
      cond['minDisplacementCc'] = r.min;
      if (r.max > 0) {
        cond['maxDisplacementCc'] = r.max;
      } else {
        cond.remove('maxDisplacementCc');
      }
      list[i]['conditions'] = cond;
      if (r.min > 0 || r.max > 0) restricted++;
    }));
    processed += batch.length;
    if (start % 400 == 0) {
      stdout.writeln('processed=$processed/${targets.length} '
          'restricted=$restricted elapsed=${sw.elapsed.inSeconds}s');
      await stdout.flush();
    }
  }

  await file.writeAsString(jsonEncode(list));
  stdout.writeln('DONE processed=$processed restricted=$restricted '
      'in ${sw.elapsed.inMinutes}m${sw.elapsed.inSeconds % 60}s');
}
