// 提携データ提供元の全国バイク駐車場案内から、
// 全47都道府県の時間貸し駐輪場データを一括取得し、
// assets/jmpsa_spots.json にまとめて書き出すワンタイムのharvestスクリプト。
//
// 実行: moto_park ディレクトリで
//   dart run tool/harvest_jmpsa.dart
//
// 仕組み(parking.js を解析して判明したエンドポイント):
//   - 都道府県の総件数: GET /society/parking/area{pref}/  (HTML中の var count=N)
//   - ページング取得:   GET /assets/module/maplist.php?id={pref}&types=1
//                            &offset={0..}&vs=1,1,1,0&sect=&locations=&search=
//   返却HTMLは JmpsaParkingService.parseHtml と同じ構造のため再利用する。
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:motopark/services/jmpsa_parking_service.dart';
import 'package:motopark/models/parking_spot.dart';

const _base = 'https://www.jmpsa.or.jp';
const _userAgent = 'Mozilla/5.0 (MotoParkHarvester)';
final _service = JmpsaParkingService();
final _countPattern = RegExp(r'var count=(\d+)');

Future<String> _get(String url) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    try {
      final r = await http
          .get(Uri.parse(url), headers: const {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 25));
      // maplist.php は Content-Type が "text/html;charset=utf-8;" と不正(末尾;)なため
      // r.body だと http パッケージが media type 解析で例外を投げる。
      // bodyBytes を直接 UTF-8 デコードして回避する。
      if (r.statusCode == 200) return utf8.decode(r.bodyBytes, allowMalformed: true);
      if (r.statusCode == 404) return '';
    } catch (_) {
      // リトライ
    }
    await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
  }
  return '';
}

Future<void> _log(String line) async {
  stdout.writeln(line);
  await stdout.flush();
}

Future<void> _save(File out, Iterable<ParkingSpot> spots) async {
  final list = spots.toList()..sort((a, b) => a.id.compareTo(b.id));
  await out.writeAsString(jsonEncode(list.map((s) => s.toJson()).toList()));
}

Future<void> main() async {
  final all = <String, ParkingSpot>{};
  final out = File('assets/jmpsa_spots.json');
  final stopwatch = Stopwatch()..start();

  for (var pref = 1; pref <= 47; pref++) {
    final areaHtml = await _get('$_base/society/parking/area$pref/');
    final m = _countPattern.firstMatch(areaHtml);
    final count = m == null ? 0 : int.parse(m.group(1)!);
    if (count == 0) {
      await _log('pref=$pref count=0 (skip)');
      continue;
    }

    final pages = (count / 10).ceil();
    final before = all.length;
    for (var offset = 0; offset < pages; offset++) {
      final html = await _get(
        '$_base/assets/module/maplist.php?id=$pref&types=1'
        '&offset=$offset&vs=1,1,1,0&sect=&locations=&search=',
      );
      if (html.isEmpty) continue;
      for (final s in _service.parseHtml(html)) {
        all.putIfAbsent(s.id, () => s);
      }
      // 提供元サーバーへの配慮としてページ間に小休止を入れる。
      await Future.delayed(const Duration(milliseconds: 120));
    }
    await _log(
      'pref=$pref count=$count pages=$pages '
      'added=${all.length - before} total=${all.length} '
      'elapsed=${stopwatch.elapsed.inSeconds}s',
    );
    // 数都道府県ごとに途中保存しておき、中断しても成果を失わないようにする。
    if (pref % 5 == 0) await _save(out, all.values);
  }

  await _save(out, all.values);
  await _log('DONE: wrote ${all.length} spots to ${out.path} '
      'in ${stopwatch.elapsed.inMinutes}m${stopwatch.elapsed.inSeconds % 60}s');
}
