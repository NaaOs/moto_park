// assets/jmpsa_spots.json の各スポットに、詳細ページの全項目を焼き込む。
//
// 取得・保存する項目:
//   TEL / 駐車場形態 / 利用可能時間 / 料金（時間貸） / 収容台数 /
//   車両制限 / バイク種別 / 管理会社 / 最終更新日   → details マップ
//   備考 → remarks、予約サービスURL → reservationUrl
//   定休日 → closedDays、料金（時間貸） → feeDescription も更新
//   バイク種別/車両制限 → conditions の排気量範囲(min/max)を導出
//
// 全スポット(予約制含む)の詳細ページを取得する。1件でも details が入っている
// スポットはスキップするため、中断しても再実行で続きから処理できる(冪等)。
//
// 実行: moto_park ディレクトリで
//   dart run tool/enrich_details.dart
//
// ※ flutter 非依存(http直叩き+インライン解析)。排気量導出のみ model を使う。
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:motopark/models/parking_spot.dart';

const _concurrency = 8;
const _userAgent = 'Mozilla/5.0 (MotoParkEnrich)';

// details に保存する項目(所在地=address, 定休日=closedDays, 備考=remarks は別扱い)。
const _keepLabels = <String>{
  'TEL',
  '駐車場形態',
  '利用可能時間',
  '料金（時間貸）',
  '収容台数',
  '車両制限',
  'バイク種別',
  '管理会社',
  '最終更新日',
};

final _rowPattern = RegExp(
  r'detail-table-ttl">(.*?)</th>\s*<td class="p-parking-detail-table-txt"[^>]*>(.*?)</td>',
  dotAll: true,
);
final _hrefPattern = RegExp(r'href="(https?://[^"]+)"');

String _decode(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll('&nbsp;', ' ');

String _clean(String s) =>
    _decode(s.replaceAll(RegExp(r'<[^>]*>'), '')).trim();

String _cleanMultiline(String s) =>
    _stripToText(s.replaceAll(
        RegExp(r'<a\b[^>]*>.*?</a>', dotAll: true, caseSensitive: false), ''));

/// <br>を改行に変換しつつタグ除去。アンカー(<a>)の中身は残す(TEL等の値向け)。
String _cleanKeep(String s) => _stripToText(s);

String _stripToText(String s) {
  final withBreaks = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  return _decode(withBreaks.replaceAll(RegExp(r'<[^>]*>'), ''))
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
}

class _Detail {
  final Map<String, String> info;
  final String remarks;
  final String? reservationUrl;
  final String? closedDays;
  _Detail(this.info, this.remarks, this.reservationUrl, this.closedDays);
}

_Detail _parse(String html) {
  final info = <String, String>{};
  var remarks = '';
  String? reservationUrl;
  String? closedDays;
  for (final m in _rowPattern.allMatches(html)) {
    final label = _clean(m.group(1)!);
    final raw = m.group(2)!;
    if (label.isEmpty) continue;
    if (label == '備考') {
      remarks = _cleanMultiline(raw);
      final href = _hrefPattern.firstMatch(raw);
      if (href != null) reservationUrl = _decode(href.group(1)!);
    } else if (label == '定休日') {
      closedDays = _cleanMultiline(raw);
    } else if (_keepLabels.contains(label)) {
      // TEL等はリンクで囲まれるため中身を残して取り出す。
      final v = _cleanKeep(raw);
      if (v.isNotEmpty) info[label] = v;
    }
  }
  return _Detail(info, remarks, reservationUrl, closedDays);
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

  // 詳細ページがあり、まだ details を持たないスポットのみ対象(冪等・再開可能)。
  final targets = <int>[];
  for (var i = 0; i < list.length; i++) {
    if (list[i]['infoUrl'] is! String) continue;
    final hasDetails = (list[i]['details'] as Map?)?.isNotEmpty ?? false;
    final hasRemarks = (list[i]['remarks'] as String?)?.isNotEmpty ?? false;
    // 一般スポット(予約URLなし)でTEL未取得のものは再取得対象にする
    // (TELはリンクで囲まれており、旧版の解析で取りこぼしていたため)。
    final isReservation = list[i]['reservationUrl'] != null;
    final hasTel = (list[i]['details'] as Map?)?.containsKey('TEL') ?? false;
    final needsTel = !isReservation && !hasTel;
    if ((!hasDetails && !hasRemarks) || needsTel) targets.add(i);
  }
  stdout.writeln('対象=${targets.length} / 全${list.length}件 (既処理はスキップ)');
  await stdout.flush();

  var processed = 0;
  var restricted = 0;
  var batchesSinceSave = 0;

  Future<void> persist() => file.writeAsString(jsonEncode(list));

  for (var start = 0; start < targets.length; start += _concurrency) {
    final batch = targets.skip(start).take(_concurrency).toList();
    await Future.wait(batch.map((i) async {
      final html = await _get(list[i]['infoUrl'] as String);
      if (html == null) return;
      final d = _parse(html);

      if (d.info.isNotEmpty) list[i]['details'] = d.info;
      if (d.remarks.isNotEmpty) list[i]['remarks'] = d.remarks;
      if (d.reservationUrl != null) list[i]['reservationUrl'] = d.reservationUrl;
      if (d.closedDays != null && d.closedDays!.isNotEmpty) {
        list[i]['closedDays'] = d.closedDays;
      }
      final fee = d.info['料金（時間貸）'];
      if (fee != null && fee.isNotEmpty) list[i]['feeDescription'] = fee;

      // バイク種別/車両制限 から排気量範囲を導出。
      final r = deriveDisplacementRange(
        bikeType: d.info['バイク種別'],
        vehicleRestriction: d.info['車両制限'],
      );
      final cond = ((list[i]['conditions'] as Map?) ?? {}).cast<String, dynamic>();
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
    batchesSinceSave++;

    // 中断対策として一定間隔で途中保存する。
    if (batchesSinceSave >= 50) {
      await persist();
      batchesSinceSave = 0;
      stdout.writeln('processed=$processed/${targets.length} '
          'restricted=$restricted elapsed=${sw.elapsed.inSeconds}s (saved)');
      await stdout.flush();
    }
  }

  await persist();
  stdout.writeln('DONE processed=$processed restricted=$restricted '
      'in ${sw.elapsed.inMinutes}m${sw.elapsed.inSeconds % 60}s');
}
