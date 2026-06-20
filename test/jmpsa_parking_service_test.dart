import 'package:flutter_test/flutter_test.dart';
import 'package:motopark/models/parking_spot.dart';
import 'package:motopark/services/jmpsa_parking_service.dart';

// JMPSA(https://www.jmpsa.or.jp/society/parking/location.php)の
// 実際のレスポンスHTMLから抜粋した2件分のサンプル。
const _sampleHtml = '''
<ul class="p-parking-prefecture-list" id="js-parking-list">
<li class="p-parking-prefecture-list-item">
	<div class="p-parking-prefecture-wrap">
		<div class="p-parking-prefecture-map">
			<p class="p-parking-prefecture-map-iframe"><iframe frameborder="0" scrolling="no" marginheight="0" marginwidth="0" src="//www.google.com/maps/embed/v1/place?key=REDACTED&q=35.689687072227706,139.70136516871673&zoom=14"></iframe></p>
		</div>
		<div class="p-parking-prefecture-txt-box">
			<p class="p-parking-prefecture-map-ttl"><a href="/society/parking/area13/p-16262.html" class="m-c-link">エコステーション21　新宿駅東南口自転車駐輪場<span class="m-arrow"></span></a></p>
			<p class="p-parking-prefecture-map-txt">新宿区新宿3-37</p>
			<div class="p-parking-prefecture-table-wrap">
				<div class="p-parking-prefecture-table">
					<div class="p-parking-prefecture-table-txt-box">
						<p class="p-parking-prefecture-table-ttl">定休日</p>
						<p class="p-parking-prefecture-table-txt">年中無休</p>
					</div>
					<div class="p-parking-prefecture-table-txt-box">
						<p class="p-parking-prefecture-table-ttl">料金</p>
						<p class="p-parking-prefecture-table-txt">最初2時間まで無料　以降　1時間毎100円</p>
					</div>
				</div>
			</div>
		</div>
	</div>
</li>
<li class="p-parking-prefecture-list-item">
	<div class="p-parking-prefecture-wrap">
		<div class="p-parking-prefecture-map">
			<p class="p-parking-prefecture-map-iframe"><iframe frameborder="0" scrolling="no" marginheight="0" marginwidth="0" src="//www.google.com/maps/embed/v1/place?key=REDACTED&q=35.6914436182118,139.698339700699&zoom=14"></iframe></p>
		</div>
		<div class="p-parking-prefecture-txt-box">
			<p class="p-parking-prefecture-map-ttl"><a href="/society/parking/area13/p-1189.html" class="m-c-link">新宿駅西口駐車場<span class="m-arrow"></span></a></p>
			<p class="p-parking-prefecture-map-txt">新宿区西新宿1西口地下街1</p>
			<div class="p-parking-prefecture-table-wrap">
				<div class="p-parking-prefecture-table">
					<div class="p-parking-prefecture-table-txt-box">
						<p class="p-parking-prefecture-table-ttl">定休日</p>
						<p class="p-parking-prefecture-table-txt">年中無休</p>
					</div>
					<div class="p-parking-prefecture-table-txt-box">
						<p class="p-parking-prefecture-table-ttl">料金</p>
						<p class="p-parking-prefecture-table-txt">30分210円　60分420円</p>
					</div>
				</div>
			</div>
		</div>
	</div>
</li>
</ul>
''';

void main() {
  test('JMPSAのlocation.php応答HTMLから駐車場一覧を抽出できる', () {
    final spots = JmpsaParkingService().parseHtml(_sampleHtml);

    expect(spots.length, 2);

    final first = spots[0];
    expect(first.id, 'jmpsa-16262');
    expect(first.name, 'エコステーション21　新宿駅東南口自転車駐輪場');
    expect(first.address, '新宿区新宿3-37');
    expect(first.latitude, closeTo(35.689687, 0.0001));
    expect(first.longitude, closeTo(139.701365, 0.0001));
    expect(first.closedDays, '年中無休');
    expect(first.feeDescription, '最初2時間まで無料　以降　1時間毎100円');
    expect(first.pricingType, PricingType.hourly);
    expect(first.official, true);
    expect(first.createdBy, 'jmpsa');
    expect(first.infoUrl, 'https://www.jmpsa.or.jp/society/parking/area13/p-16262.html');

    final second = spots[1];
    expect(second.id, 'jmpsa-1189');
    expect(second.name, '新宿駅西口駐車場');
    expect(second.feeDescription, '30分210円　60分420円');
  });

  test('詳細ページHTMLから備考・予約URL・写真を抽出できる', () {
    final detail = JmpsaParkingService().parseDetail(_detailHtml);

    expect(
      detail.remarks,
      'ご利用の際は駐車場予約サービス「akippa」のサイトからご予約ください。\nバイクも駐車可能です。',
    );
    expect(
      detail.reservationUrl,
      'https://www.akippa.com/parking/40540de5201ecb26036a43d2e9f213ef?utm_source=jmpsa&utm_medium=referral&utm_campaign=jmpsa',
    );
    expect(detail.photoUrls, [
      'https://www.jmpsa.or.jp/prg_img/img/40540de5201ecb26036a43d2e9f213ef01.jpg',
      'https://www.jmpsa.or.jp/prg_img/img/40540de5201ecb26036a43d2e9f213ef02.jpg',
    ]);
  });

  test('詳細ページからバイク種別・収容台数・車両制限・利用可能時間を抽出できる', () {
    final detail = JmpsaParkingService().parseDetail(_detailInfoHtml);

    expect(detail.bikeType, '125cc以下');
    expect(detail.capacity, '44台');
    expect(detail.vehicleRestriction, '排気量50cc以下は不可');
    expect(detail.availableHours, '24H');
    expect(detail.info['所在地'], '練馬区練馬1-17-5');
  });

  test('テーブル行が無い詳細ページは空のJmpsaSpotDetailを返す', () {
    final detail = JmpsaParkingService().parseDetail(
      '<div class="p-parking-detail-wrap"><p>準備中</p></div>',
    );
    expect(detail.isEmpty, true);
  });
}

// バイク種別・収容台数・車両制限などを含む詳細ページのサンプル。
const _detailInfoHtml = '''
<table class="p-parking-detail-table"><tbody>
<tr class="p-parking-detail-table-tr"><th class="p-parking-detail-table-ttl">所在地</th><td class="p-parking-detail-table-txt" style="word-break: break-all;">練馬区練馬1-17-5</td></tr>
<tr class="p-parking-detail-table-tr"><th class="p-parking-detail-table-ttl">バイク種別</th><td class="p-parking-detail-table-txt" style="word-break: break-all;">125cc以下</td></tr>
<tr class="p-parking-detail-table-tr"><th class="p-parking-detail-table-ttl">利用可能時間</th><td class="p-parking-detail-table-txt" style="word-break: break-all;">24H</td></tr>
<tr class="p-parking-detail-table-tr"><th class="p-parking-detail-table-ttl">収容台数</th><td class="p-parking-detail-table-txt" style="word-break: break-all;">44台</td></tr>
<tr class="p-parking-detail-table-tr"><th class="p-parking-detail-table-ttl">車両制限</th><td class="p-parking-detail-table-txt" style="word-break: break-all;">排気量50cc以下は不可</td></tr>
</tbody></table>
''';

// JMPSAの予約制駐車場の詳細ページから抜粋したサンプル(写真は重複ありで掲載される)。
const _detailHtml = '''
<div class="p-parking-detail-wrap">
<p class="p-parking-detail-img"><img src="/prg_img/img/40540de5201ecb26036a43d2e9f213ef01.jpg" alt=""></p>
<p class="p-parking-detail-img"><img src="/prg_img/img/40540de5201ecb26036a43d2e9f213ef01.jpg" alt=""></p>
<p class="p-parking-detail-img"><img src="/prg_img/img/40540de5201ecb26036a43d2e9f213ef02.jpg" alt=""></p>
<table class="p-parking-detail-table"><tbody>
<tr class="p-parking-detail-table-tr"><th class="p-parking-detail-table-ttl">所在地</th><td class="p-parking-detail-table-txt" style="word-break: break-all;">新宿区新宿7-2-2</td></tr>
<tr class="p-parking-detail-table-tr"><th class="p-parking-detail-table-ttl">備考</th><td class="p-parking-detail-table-txt" style="word-break: break-all;">ご利用の際は駐車場予約サービス「akippa」のサイトからご予約ください。<br><a href="https://www.akippa.com/parking/40540de5201ecb26036a43d2e9f213ef?utm_source=jmpsa&amp;utm_medium=referral&amp;utm_campaign=jmpsa" target="_blank">予約ページ</a><br>バイクも駐車可能です。</td></tr>
</tbody></table>
</div>
''';
