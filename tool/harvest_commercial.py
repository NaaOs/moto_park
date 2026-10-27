"""商業施設(ショッピングモール・百貨店・スーパー・ホームセンター等)に併設された
バイク駐輪場を収集し、assets/commercial_spots.json に書き出すharvestスクリプト。

データ源:
  1. OpenStreetMap (Overpass API, ODbL)
     - 国内の amenity=motorcycle_parking と、商業施設(shop=mall 等)の範囲を取得し、
       施設の敷地内(範囲+約30m) または 80m以内で「顧客用」と明示されたものを採用する。
     - 駅前・公営・コインパーキング系(既存の時間貸しデータと重複しやすい)は名称で除外する。
  2. 各施設の公式サイト (tool/commercial_curated.json)
     - 料金・台数・利用時間を公式ページで確認できた施設。OSMの同一施設分より優先する。
  住所は OSM Nominatim の逆ジオコーディングで補完する(1リクエスト/秒の利用規約を守る)。
  3. Google マップの検索結果
     - OSMの位置は施設の一部(駐輪場の点や敷地の中心)で施設の代表地点とずれることがあるため、
       施設名で Google マップを検索し、現在の位置から1.5km以内に見つかった施設の座標・住所で置き換える。
       見つからない施設(支店名のないチェーン店など)は元の位置のまま残す。
     - 置き換えの結果、同じ地点になった同一施設の複数レコードは1件にまとめる。

実行: moto_park ディレクトリで
  python tool/harvest_commercial.py            # 取得結果は tool/backup/commercial_cache にキャッシュ
  python tool/harvest_commercial.py --refresh  # キャッシュを無視して取り直す
"""
import json
import math
import os
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, 'tool', 'backup', 'commercial_cache')
CURATED = os.path.join(ROOT, 'tool', 'commercial_curated.json')
OUT = os.path.join(ROOT, 'assets', 'commercial_spots.json')
UA = 'MotoPark-harvester/1.0 (+https://github.com/NaaOs/moto_park)'
OVERPASS = 'https://overpass-api.de/api/interpreter'
NOMINATIM = 'https://nominatim.openstreetmap.org'
REFRESH = '--refresh' in sys.argv

SHOP_KINDS = 'mall|department_store|supermarket|doityourself|hardware|wholesale|electronics|furniture|general|variety_store'
QUERIES = {
    'moto': 'nwr["amenity"="motorcycle_parking"](area.jp);out center tags;',
    'shops': (f'(way["shop"~"^({SHOP_KINDS})$"](area.jp);relation["shop"~"^({SHOP_KINDS})$"](area.jp);'
              'way["landuse"="retail"]["name"](area.jp);relation["landuse"="retail"]["name"](area.jp););out tags bb;'),
    'shopnodes': f'node["shop"~"^({SHOP_KINDS})$"]["name"](area.jp);out body;',
}

CATEGORY = {
    'mall': 'ショッピングモール', 'department_store': '百貨店', 'supermarket': 'スーパー',
    'electronics': '家電量販店', 'furniture': '家具・インテリア店', 'doityourself': 'ホームセンター',
    'hardware': 'ホームセンター', 'wholesale': '会員制倉庫店', 'variety_store': 'ディスカウントストア',
    'general': '総合店',
}
# 施設の種類の優先度(重なっている範囲はモール等の大きい施設を採用する)
RANK = {'mall': 0, 'department_store': 1, 'wholesale': 2, 'doityourself': 3, 'hardware': 3,
        'electronics': 4, 'furniture': 4, 'supermarket': 5, 'general': 6, 'variety_store': 6}
# 公共・駅前・コインパーキング系、施設外の駐輪場を示す名称
PUBLIC = re.compile(
    r'駅|エコステーション|ECO|Eco|NPC|タイムズ|Times|従業員|社員|J\.PARK|JKS|ＪＫＳ|AP|サイカ|Cyca|サイクル|'
    r'パークイット|市営|区営|町営|村営|都営|県営|公営|自転車等|自転車駐車場|放置|機械式|丁目|^第|JR|道路|公園|'
    r'学校|高校|大学|病院|役所|センター|図書館|集積|保管所|月極|定期')
FAC_EXCLUDE = re.compile(r'商店街|駅|ターミナル|サービスエリア|パーキングエリア|EXPASA|PA$|SA$|'
                         r'リサイクル|中華街|美観地区|城彩苑|ＪＫＳ|JKS|与島')
PAD = 0.0003  # 施設範囲の外側に許容する余白(約30m)
# 名称では判別できない、施設外(公共)の駐輪場として目視で除外したOSM要素
EXCLUDE_OSM = {
    'way/585105492',  # 木屋町三条南バイク駐輪場(京都BALとは別の公共駐輪場)
}
# モール系の名称なのにOSM上は百貨店等になっている施設をショッピングモールとして扱う
MALL_NAME = re.compile(r'ららぽーと|モール|アウトレット|ショッピングセンター|ショッピングパーク')
PREFECTURES = ('北海道 青森県 岩手県 宮城県 秋田県 山形県 福島県 茨城県 栃木県 群馬県 埼玉県 千葉県 東京都 神奈川県 '
               '新潟県 富山県 石川県 福井県 山梨県 長野県 岐阜県 静岡県 愛知県 三重県 滋賀県 京都府 大阪府 兵庫県 '
               '奈良県 和歌山県 鳥取県 島根県 岡山県 広島県 山口県 徳島県 香川県 愛媛県 高知県 福岡県 佐賀県 '
               '長崎県 熊本県 大分県 宮崎県 鹿児島県 沖縄県').split()


def http_get(url, data=None):
    req = urllib.request.Request(url, data=data, headers={'User-Agent': UA, 'Accept': 'application/json'})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=600) as r:
                return r.read().decode('utf-8')
        except Exception as e:  # noqa: BLE001 - リトライして最後に投げる
            if attempt == 3:
                raise
            print(f'  retry ({e})')
            time.sleep(5 * (attempt + 1))


def cached(name, fetch):
    path = os.path.join(CACHE, name)
    if not REFRESH and os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    data = fetch()
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False)
    return data


def overpass(key):
    def fetch():
        print(f'Overpass: {key} ...')
        q = f'[out:json][timeout:480];area["ISO3166-1"="JP"][admin_level=2]->.jp;{QUERIES[key]}'
        body = urllib.parse.urlencode({'data': q}).encode()
        return json.loads(http_get(OVERPASS, body))['elements']
    return cached(f'{key}.json', fetch)


def dist(a, b, c, d):
    r = 6371000
    p1, p2 = math.radians(a), math.radians(c)
    h = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(d - b) / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def pos(e):
    if 'lat' in e:
        return e['lat'], e['lon']
    if 'center' in e:
        return e['center']['lat'], e['center']['lon']
    b = e['bounds']
    return (b['minlat'] + b['maxlat']) / 2, (b['minlon'] + b['maxlon']) / 2


def inside(b, lat, lon):
    return b['minlat'] - PAD <= lat <= b['maxlat'] + PAD and b['minlon'] - PAD <= lon <= b['maxlon'] + PAD


def label(t):
    return t.get('name:ja') or t.get('name') or ''


def facility_name(t):
    n = label(t)
    branch = (t.get('branch:ja') or t.get('branch') or '').split(';')[0]
    if branch and branch not in n:
        n = f'{n} {branch}'
    return n


# ── 逆ジオコーディング(住所補完) ─────────────────────────────────────────────
_geo_cache_path = os.path.join(CACHE, 'geocode.json')
_geo = {}


def _save_geo():
    with open(_geo_cache_path, 'w', encoding='utf-8') as f:
        json.dump(_geo, f, ensure_ascii=False)


def _nominatim(path):
    time.sleep(1.1)  # Nominatim 利用規約: 1リクエスト/秒
    return json.loads(http_get(f'{NOMINATIM}/{path}'))


def reverse_address(lat, lon):
    key = f'{lat:.6f},{lon:.6f}'
    if key not in _geo:
        try:
            r = _nominatim(f'reverse?format=jsonv2&accept-language=ja&zoom=18&lat={lat}&lon={lon}')
            _geo[key] = r.get('address', {})
        except Exception:  # noqa: BLE001 - 住所なしで続行する
            _geo[key] = {}
        _save_geo()
    a = _geo[key]
    # 東京都などは province が無く ISO コードのみ返るため、コードから都道府県名を補う
    pref = a.get('province') or a.get('state')
    iso = a.get('ISO3166-2-lvl4', '')
    if not pref and iso.startswith('JP-') and iso[3:].isdigit():
        pref = PREFECTURES[int(iso[3:]) - 1]
    parts = [pref] + [a.get(k) for k in ('county', 'city', 'town', 'village', 'city_district',
                                         'suburb', 'hamlet', 'quarter', 'neighbourhood')]
    parts = [p for i, p in enumerate(parts) if p and p not in parts[:i]]
    # 「鹿島田」「鹿島田一丁目」のように次の要素が前の要素を含む場合は前を省く
    parts = [p for i, p in enumerate(parts) if not (i + 1 < len(parts) and parts[i + 1].startswith(p))]
    return ''.join(parts)


def search_position(q):
    key = f'search:{q}'
    if key not in _geo:
        r = _nominatim(f'search?format=jsonv2&accept-language=ja&countrycodes=jp&limit=1&q={urllib.parse.quote(q)}')
        _geo[key] = [float(r[0]['lat']), float(r[0]['lon'])] if r else None
        _save_geo()
    return _geo[key]


# ── 出力レコード(ParkingSpot.fromJson 互換) ───────────────────────────────────
# ── Google マップ検索(施設の代表座標) ────────────────────────────────────────
GOOGLE_SEARCH = 'https://www.google.com/search?tbm=map&hl=ja&gl=jp&q='
BROWSER_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
GOOGLE_MAX_SHIFT = 1500  # 現在の位置からこれ以上離れた検索結果は別店舗とみなして採用しない(m)
GOOGLE_MAX_SHIFT_BY_NAME = 20000  # 施設名が一致する場合に許容する距離(元の位置自体が不正確な場合の救済)(m)
_google_cache_path = os.path.join(CACHE, 'google.json')
_google = {}


def google_places(q):
    """Google マップで q を検索し、[(名称, 緯度, 経度, 住所, 種別)] を返す。
    種別 'place' は検索結果の施設、'view' は検索後に地図が移動する先(名称に施設名を含む場合のみ使う)。"""
    if q not in _google:
        time.sleep(1.5)
        try:
            req = urllib.request.Request(GOOGLE_SEARCH + urllib.parse.quote(q),
                                         headers={'User-Agent': BROWSER_UA, 'Accept-Language': 'ja'})
            with urllib.request.urlopen(req, timeout=30) as r:
                raw = r.read().decode('utf-8')
            d = json.loads(raw[raw.index('\n') + 1:])  # 先頭の )]}' を除く
            found = []
            for res in (d[0][1] or []):
                if isinstance(res, list) and len(res) > 14 and isinstance(res[14], list):
                    p = res[14]
                    if len(p) > 11 and p[9]:
                        addr = p[39] if len(p) > 39 and isinstance(p[39], str) else ''
                        found.append([p[11], p[9][2], p[9][3], addr, 'place'])
            # 一致する施設が一意に決まらない場合も、地図の移動先が施設そのものなら名称に施設名が入る
            view = d[37] if len(d) > 37 and isinstance(d[37], list) and len(d[37]) > 2 else None
            if view and isinstance(view[2], list) and view[2] and view[2][0][3]:
                v = view[2][0]
                found.append([v[4] or view[1] or '', v[3][2], v[3][3], '', 'view'])
            _google[q] = found
        except Exception as e:  # noqa: BLE001 - 取得できなければ元の位置を使う
            print(f'  google failed: {q} ({e})')
            return []
        with open(_google_cache_path, 'w', encoding='utf-8') as f:
            json.dump(_google, f, ensure_ascii=False)
    return _google[q]


def _municipality(address):
    """「東京都世田谷区南烏山五丁目」→「東京都世田谷区」(市区町村まで)。"""
    m = re.match(r'(.+?[都道府県])?(.+?郡)?(.+?市)?(.+?[区町村])?', address)
    return ''.join(g for g in m.groups() if g) if m else address


def _norm(s):
    return re.sub(r'[\s・･]', '', unicodedata.normalize('NFKC', s)).lower()


def relocate_by_google(rec):
    """施設名で Google マップを検索し、近くで見つかれば座標と住所を置き換える。成功時 True。

    採用条件:
      - 検索結果の施設('place'): 現在の位置から1.5km以内、または施設名を含み20km以内(施設名6文字以上)
      - 地図の移動先('view'): 名称に施設名を含み20km以内(地域名だけの移動先=曖昧な検索は使わない)
    """
    fac = rec['details'].get('施設名') or rec['name']
    nfac = _norm(fac)
    # 公式サイトで確認した施設は名称が一意なため、名称が一致すれば距離を問わない
    # (元の位置が Nominatim の検索結果で、大きくずれている場合がある)
    official = not rec['id'].startswith('commercial-osm-')
    max_by_name = float('inf') if official else GOOGLE_MAX_SHIFT_BY_NAME
    queries = [f"{fac} {rec['address']}", f"{fac} {_municipality(rec['address'])}", fac, fac.replace(' ', '')]
    for q in dict.fromkeys(q.strip() for q in queries):
        cands = []
        for name, lat, lon, addr, *kind in google_places(q):
            d = dist(rec['latitude'], rec['longitude'], lat, lon)
            named = nfac in _norm(name) and d <= max_by_name
            if (kind or ['place'])[0] == 'view':
                ok = named
                # 移動先の名称は「住所 施設名」の形式なので、先頭の住所部分を住所として使う
                head = name.split()[0] if name.split() else ''
                addr = head if re.match(r'.+?[都道府県]', head) else ''
            else:
                ok = d <= GOOGLE_MAX_SHIFT or (named and len(nfac) >= 6)
            if ok:
                cands.append((d, name, lat, lon, addr))
        if cands:
            _, name, lat, lon, addr = min(cands)
            rec['latitude'], rec['longitude'] = round(lat, 7), round(lon, 7)
            if addr:
                rec['address'] = re.sub(r'^〒\d{3}-\d{4}\s*', '', addr)
            rec['details']['位置'] = 'Google マップの施設位置'
            return True
    return False


def spot(sid, name, lat, lon, address, fee, details, remarks, url, cond):
    rec = {
        'id': sid, 'name': name, 'address': address, 'latitude': round(lat, 7), 'longitude': round(lon, 7),
        'official': True, 'conditions': cond, 'pricingType': 'hourly', 'feeDescription': fee,
        'closedDays': '施設の営業日・営業時間に準じます', 'infoUrl': url, 'photoUrls': [], 'streetViewUrl': None,
        'status': 'active', 'reportCount': 0, 'createdBy': 'commercial', 'createdAt': None,
        'details': {k: v for k, v in details.items() if v},
    }
    if remarks:
        rec['remarks'] = remarks
    return rec


def conditions(tags=None, min_cc=0):
    tags = tags or {}
    s = tags.get('surface')
    surface = ('asphalt' if s in ('asphalt', 'paved', 'concrete') else
               'gravel' if s in ('gravel', 'fine_gravel', 'compacted') else
               'soil' if s in ('dirt', 'ground', 'sand', 'earth') else 'unknown')
    return {'minDisplacementCc': min_cc, 'roofed': tags.get('covered') == 'yes', 'groundLockable': False,
            'surface': surface, 'flat': False}


def main():
    global _geo
    os.makedirs(CACHE, exist_ok=True)
    if os.path.exists(_geo_cache_path):
        with open(_geo_cache_path, encoding='utf-8') as f:
            _geo = json.load(f)
    moto = overpass('moto')
    shops = overpass('shops')
    nodes = overpass('shopnodes')
    by_ref = {f"{e['type']}/{e['id']}": e for e in shops + nodes}

    areas, points = [], []
    for s in shops:
        t = s.get('tags', {})
        if not label(t) or 'bounds' not in s:
            continue
        b = s['bounds']
        size = (dist(b['minlat'], b['minlon'], b['maxlat'], b['minlon'])
                * dist(b['minlat'], b['minlon'], b['minlat'], b['maxlon']))
        if size > 1.5e6:  # 1.5km²超(商店街・地区単位)は施設とみなさない
            continue
        kind = t.get('shop') or ('mall' if t.get('landuse') == 'retail' else 'other')
        areas.append(dict(name=facility_name(t), kind=kind, b=b, size=size, c=pos(s)))
    for s in nodes:
        t = s.get('tags', {})
        points.append(dict(name=facility_name(t), kind=t.get('shop'), c=(s['lat'], s['lon'])))

    # 1) 公式サイトで確認した施設
    with open(CURATED, encoding='utf-8') as f:
        curated = json.load(f)
    claimed = []  # 公式分で採用した施設範囲(同一施設のOSM分を重複させないため)
    out = []
    for c in curated:
        ref = by_ref.get(c.get('osm', ''))
        if ref is not None:
            lat, lon = pos(ref)
            bounds = ref.get('bounds')
        else:
            lat, lon = search_position(c['query'])
            bounds = None
        if bounds:
            # 施設範囲内にOSMのバイク駐輪場があれば、施設の中心ではなくその位置にピンを立てる
            for m in moto:
                mlat, mlon = pos(m)
                if inside(bounds, mlat, mlon) and m.get('tags', {}).get('access') not in ('private', 'no'):
                    lat, lon = mlat, mlon
                    break
        else:
            bounds = {'minlat': lat - 0.002, 'maxlat': lat + 0.002, 'minlon': lon - 0.002, 'maxlon': lon + 0.002}
        claimed.append(bounds)
        details = {
            '駐車場形態': f"商業施設併設（{c['category']}）", '施設名': c['facility'],
            'バイク置場の場所': c.get('location'), '利用可能時間': c.get('hours'), '料金（時間貸）': c['fee'],
            '収容台数': c.get('capacity'), '車両制限': c.get('restriction'), '情報源': '施設公式サイト',
        }
        out.append(spot(f"commercial-{c['key']}", c['name'], lat, lon,
                        c.get('address') or reverse_address(lat, lon), c['fee'], details,
                        c.get('remarks', ''), c['url'], conditions(min_cc=c.get('minCc', 0))))

    # 2) OSM から施設併設のバイク駐輪場を抽出
    kept = []
    for m in moto:
        t = m.get('tags', {})
        if t.get('access') in ('private', 'no', 'permit') or f"{m['type']}/{m['id']}" in EXCLUDE_OSM:
            continue
        lat, lon = pos(m)
        name = label(t)
        if name and PUBLIC.search(name):
            continue
        if any(inside(b, lat, lon) for b in claimed):
            continue
        cands = sorted((RANK.get(a['kind'], 9), -a['size'], i)
                       for i, a in enumerate(areas) if inside(a['b'], lat, lon))
        if cands:
            fac = areas[cands[0][2]]
        else:
            best = None
            for p in points + areas:
                d = dist(lat, lon, *p['c'])
                if d <= 80 and (best is None or d < best[0]):
                    best = (d, p)
            # 近接のみの一致は「顧客用」と明示されたもの、または施設名を含むものだけ採用
            if not best or not (t.get('access') == 'customers' or (name and best[1]['name'][:3] in name)):
                continue
            fac = best[1]
        if fac['kind'] not in CATEGORY or not fac['name'] or FAC_EXCLUDE.search(fac['name']):
            continue
        # 同一施設で40m以内の重複は1件にまとめる
        if any(k[0] == fac['name'] and dist(k[1], k[2], lat, lon) < 40 for k in kept):
            continue
        kept.append((fac['name'], lat, lon))

        if name and fac['name'] in name:
            title = name
        elif name:
            title = f"{fac['name']}（{name}）"
        else:
            title = f"{fac['name']} バイク駐輪場"
        kind = 'mall' if MALL_NAME.search(fac['name']) else fac['kind']
        fee = t.get('charge') or {'no': '無料（施設利用者向け）', 'yes': '有料（料金は現地表示をご確認ください）'}.get(
            t.get('fee'), '料金は現地表示をご確認ください（施設利用者向け）')
        details = {
            '駐車場形態': f"商業施設併設（{CATEGORY[kind]}）", '施設名': fac['name'],
            '利用可能時間': '24時間' if t.get('opening_hours') == '24/7' else t.get('opening_hours'),
            '収容台数': f"{t['capacity']}台" if t.get('capacity', '').isdigit() else None,
            '屋根': {'yes': 'あり', 'no': 'なし'}.get(t.get('covered')),
            '情報源': 'OpenStreetMap',
        }
        remarks = t.get('description') or t.get('note') or ''
        out.append(spot(f"commercial-osm-{m['type'][0]}{m['id']}", title, lat, lon, reverse_address(lat, lon),
                        fee, details, remarks, f"https://www.openstreetmap.org/{m['type']}/{m['id']}",
                        conditions(t)))

    # 3) Google マップの施設位置に合わせる
    global _google
    if os.path.exists(_google_cache_path):
        with open(_google_cache_path, encoding='utf-8') as f:
            _google = json.load(f)
    missed = [rec['name'] for rec in out if not relocate_by_google(rec)]
    # 同一施設が同じ地点になった場合は1件にまとめる(公式サイト分を優先)
    out.sort(key=lambda s: (s['id'].startswith('commercial-osm-'), s['id']))
    seen, merged = set(), []
    for rec in out:
        key = (rec['details'].get('施設名'), round(rec['latitude'], 5), round(rec['longitude'], 5))
        if key in seen:
            continue
        seen.add(key)
        merged.append(rec)
    print(f'google: {len(out) - len(missed)} relocated, {len(missed)} kept, {len(out) - len(merged)} merged')
    with open(os.path.join(CACHE, 'google_missed.txt'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(missed))
    out = merged

    out.sort(key=lambda s: s['id'])
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
    print(f'{len(out)} spots ({len(curated)} official) -> {os.path.relpath(OUT, ROOT)}')


if __name__ == '__main__':
    main()
