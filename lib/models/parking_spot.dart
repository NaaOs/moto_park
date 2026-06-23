/// 路面状況。土・砂利はスタンドが沈んで転倒するリスクがあるためライダーには重要な情報。
enum GroundSurface { asphalt, gravel, soil, unknown }

/// 料金区分。JMPSA(日本二輪車普及安全協会)の駐車場検索が採用する区分に合わせる。
/// 本アプリでは「時間貸し」のみを地図に表示する。
enum PricingType { hourly, monthly }

/// モデレーション状態。報告が一定数を超えると自動的に非表示になる。
enum SpotStatus { active, hidden }

GroundSurface surfaceFromString(String? value) {
  switch (value) {
    case 'asphalt':
      return GroundSurface.asphalt;
    case 'gravel':
      return GroundSurface.gravel;
    case 'soil':
      return GroundSurface.soil;
    default:
      return GroundSurface.unknown;
  }
}

String surfaceToString(GroundSurface surface) => surface.name;

PricingType pricingTypeFromString(String? value) {
  return value == 'monthly' ? PricingType.monthly : PricingType.hourly;
}

String pricingTypeToString(PricingType type) => type.name;

/// バイク種別・車両制限の文言から、駐輪可能な排気量範囲(下限min・上限max, 0=制限なし)を導く。
/// JMPSAの「バイク種別」(例:125cc以下)を優先し、無ければ「車両制限」の文章から抽出する。
({int min, int max}) deriveDisplacementRange({String? bikeType, String? vehicleRestriction}) {
  final bt = bikeType?.trim();
  if (bt != null && bt.isNotEmpty) {
    final r = _rangeFromToken(bt);
    if (r != null) return r;
  }
  final vr = vehicleRestriction?.trim();
  if (vr != null && vr.isNotEmpty) {
    final first = vr.split('\n').first;
    if (first.contains('制限はありません') || first.contains('制限なし')) {
      return (min: 0, max: 0);
    }
    final m = _ccPattern.firstMatch(first);
    if (m != null) {
      final after = first.substring(m.end).trimLeft();
      final negated = after.startsWith('は不可') ||
          after.startsWith('不可') ||
          after.startsWith('は駐車不可');
      return _applyKind(int.parse(m.group(1)!), m.group(2)!, negated);
    }
  }
  return (min: 0, max: 0);
}

/// 排気量範囲を表示用ラベルにする(例: min125,max0 →「125cc以上」)。
String displacementLabel(int min, int max) {
  if (min <= 0 && max <= 0) return '排気量制限なし';
  if (min > 0 && max <= 0) return '${min}cc以上';
  if (min <= 0 && max > 0) return '${max}cc以下';
  return '$min〜${max}cc';
}

final _ccPattern = RegExp(r'(\d+)\s*cc\s*(以上|以下|未満|超)');

({int min, int max})? _rangeFromToken(String s) {
  final m = _ccPattern.firstMatch(s);
  if (m == null) return null;
  return _applyKind(int.parse(m.group(1)!), m.group(2)!, false);
}

({int min, int max}) _applyKind(int n, String kind, bool negated) {
  switch (kind) {
    case '以上':
      return negated ? (min: 0, max: n - 1) : (min: n, max: 0);
    case '以下':
      return negated ? (min: n + 1, max: 0) : (min: 0, max: n);
    case '未満':
      return negated ? (min: n, max: 0) : (min: 0, max: n - 1);
    case '超':
      return negated ? (min: 0, max: n) : (min: n + 1, max: 0);
  }
  return (min: 0, max: 0);
}

/// ライダー特化の駐輪条件。車の駐車場には無い視点で絞り込みができる。
class SpotConditions {
  final int minDisplacementCc; // この値以上の排気量が駐輪可能 (0 = 下限なし)
  final int maxDisplacementCc; // この値以下の排気量が駐輪可能 (0 = 上限なし)
  final bool roofed; // 屋根あり
  final bool groundLockable; // 地球ロック(固定物への施錠)可
  final GroundSurface surface; // 路面状況
  final bool flat; // 傾斜なし

  const SpotConditions({
    this.minDisplacementCc = 0,
    this.maxDisplacementCc = 0,
    this.roofed = false,
    this.groundLockable = false,
    this.surface = GroundSurface.unknown,
    this.flat = false,
  });

  /// 排気量 cc のバイクが駐輪可能か(範囲内か)。
  bool accepts(int cc) {
    if (minDisplacementCc > 0 && cc < minDisplacementCc) return false;
    if (maxDisplacementCc > 0 && cc > maxDisplacementCc) return false;
    return true;
  }

  /// 排気量制限の表示ラベル(例:「125cc以下」)。制限なしなら「排気量制限なし」。
  String get displacementText => displacementLabel(minDisplacementCc, maxDisplacementCc);

  /// 排気量の制限があるか。
  bool get hasDisplacementLimit => minDisplacementCc > 0 || maxDisplacementCc > 0;

  factory SpotConditions.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SpotConditions();
    return SpotConditions(
      minDisplacementCc: (map['minDisplacementCc'] as num?)?.toInt() ?? 0,
      maxDisplacementCc: (map['maxDisplacementCc'] as num?)?.toInt() ?? 0,
      roofed: map['roofed'] as bool? ?? false,
      groundLockable: map['groundLockable'] as bool? ?? false,
      surface: surfaceFromString(map['surface'] as String?),
      flat: map['flat'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'minDisplacementCc': minDisplacementCc,
        if (maxDisplacementCc > 0) 'maxDisplacementCc': maxDisplacementCc,
        'roofed': roofed,
        'groundLockable': groundLockable,
        'surface': surfaceToString(surface),
        'flat': flat,
      };
}

class ParkingSpot {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final bool official; // 公式 / 非公式(クラウドソーシング登録)
  final SpotConditions conditions;
  final PricingType pricingType; // 時間貸し / 月極(本アプリは時間貸しのみ表示)
  final String feeDescription; // 料金の説明(例: 100円/60分)
  final String closedDays; // 定休日・休業情報(例: なし(年中無休))
  final String? infoUrl; // 詳細情報の参照元(JMPSAの駐車場検索など)
  final List<String> photoUrls;
  final String? streetViewUrl; // 進入路確認用
  final SpotStatus status;
  final int reportCount;
  final String createdBy;
  final DateTime? createdAt;

  /// JMPSA詳細ページの各項目(ラベル→値)。harvest時に焼き込む。
  /// 例: TEL / 駐車場形態 / 利用可能時間 / 料金（時間貸） / 収容台数 /
  ///     車両制限 / バイク種別 / 管理会社 / 最終更新日。
  final Map<String, String> details;
  final String remarks; // 備考(予約案内文など)
  final String? reservationUrl; // 予約サービス(akippa/特P等)のURL

  const ParkingSpot({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.official = false,
    this.conditions = const SpotConditions(),
    this.pricingType = PricingType.hourly,
    this.feeDescription = '',
    this.closedDays = '',
    this.infoUrl,
    this.photoUrls = const [],
    this.streetViewUrl,
    this.status = SpotStatus.active,
    this.reportCount = 0,
    required this.createdBy,
    this.createdAt,
    this.details = const {},
    this.remarks = '',
    this.reservationUrl,
  });

  /// 予約が必要かどうか。JMPSAデータでは予約制の施設名が「【予約制：◯◯】」で
  /// 始まるため、名称から判定する(akippa・特P・いつでもニリーン等)。
  bool get requiresReservation => name.contains('予約制');

  // ── JMPSA詳細項目へのアクセサ(無ければ null) ──
  String? get tel => _detail('TEL');
  String? get parkingType => _detail('駐車場形態'); // 駐車場形態(時間貸 等)
  String? get availableHours => _detail('利用可能時間');
  String? get hourlyFee => _detail('料金（時間貸）');
  String? get capacity => _detail('収容台数');
  String? get vehicleRestriction => _detail('車両制限');
  String? get bikeType => _detail('バイク種別'); // 対応するバイクのサイズ区分
  String? get managementCompany => _detail('管理会社');
  String? get lastUpdated => _detail('最終更新日');

  /// 焼き込み済みの詳細情報を持っているか(詳細カードの表示判定に使う)。
  bool get hasDetails => details.isNotEmpty || remarks.isNotEmpty || reservationUrl != null;

  String? _detail(String key) {
    final v = details[key];
    return (v == null || v.isEmpty) ? null : v;
  }

  factory ParkingSpot.fromJson(Map<String, dynamic> json) {
    return ParkingSpot(
      id: json['id'] as String,
      name: json['name'] as String? ?? '名称未設定',
      address: json['address'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      official: json['official'] as bool? ?? false,
      conditions: SpotConditions.fromMap(json['conditions'] as Map<String, dynamic>?),
      pricingType: pricingTypeFromString(json['pricingType'] as String?),
      feeDescription: json['feeDescription'] as String? ?? '',
      closedDays: json['closedDays'] as String? ?? '',
      infoUrl: json['infoUrl'] as String?,
      photoUrls: (json['photoUrls'] as List?)?.cast<String>() ?? const [],
      streetViewUrl: json['streetViewUrl'] as String?,
      status: (json['status'] as String?) == 'hidden' ? SpotStatus.hidden : SpotStatus.active,
      reportCount: (json['reportCount'] as num?)?.toInt() ?? 0,
      createdBy: json['createdBy'] as String? ?? '',
      createdAt: json['createdAt'] == null ? null : DateTime.parse(json['createdAt'] as String),
      details: (json['details'] as Map?)?.map((k, v) => MapEntry(k as String, v as String)) ?? const {},
      remarks: json['remarks'] as String? ?? '',
      reservationUrl: json['reservationUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'official': official,
        'conditions': conditions.toMap(),
        'pricingType': pricingTypeToString(pricingType),
        'feeDescription': feeDescription,
        'closedDays': closedDays,
        'infoUrl': infoUrl,
        'photoUrls': photoUrls,
        'streetViewUrl': streetViewUrl,
        'status': status.name,
        'reportCount': reportCount,
        'createdBy': createdBy,
        'createdAt': createdAt?.toIso8601String(),
        // サイズ削減のため空の項目は出力しない。
        if (details.isNotEmpty) 'details': details,
        if (remarks.isNotEmpty) 'remarks': remarks,
        if (reservationUrl != null) 'reservationUrl': reservationUrl,
      };

  ParkingSpot copyWith({
    SpotStatus? status,
    int? reportCount,
  }) {
    return ParkingSpot(
      id: id,
      name: name,
      address: address,
      latitude: latitude,
      longitude: longitude,
      official: official,
      conditions: conditions,
      pricingType: pricingType,
      feeDescription: feeDescription,
      closedDays: closedDays,
      infoUrl: infoUrl,
      photoUrls: photoUrls,
      streetViewUrl: streetViewUrl,
      status: status ?? this.status,
      reportCount: reportCount ?? this.reportCount,
      createdBy: createdBy,
      createdAt: createdAt,
      details: details,
      remarks: remarks,
      reservationUrl: reservationUrl,
    );
  }
}
