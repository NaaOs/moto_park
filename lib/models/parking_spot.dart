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

/// ライダー特化の駐輪条件。車の駐車場には無い視点で絞り込みができる。
class SpotConditions {
  final int minDisplacementCc; // この値以上の排気量の車種が駐輪可能 (0 = 制限なし)
  final bool roofed; // 屋根あり
  final bool groundLockable; // 地球ロック(固定物への施錠)可
  final GroundSurface surface; // 路面状況
  final bool flat; // 傾斜なし

  const SpotConditions({
    this.minDisplacementCc = 0,
    this.roofed = false,
    this.groundLockable = false,
    this.surface = GroundSurface.unknown,
    this.flat = false,
  });

  factory SpotConditions.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SpotConditions();
    return SpotConditions(
      minDisplacementCc: (map['minDisplacementCc'] as num?)?.toInt() ?? 0,
      roofed: map['roofed'] as bool? ?? false,
      groundLockable: map['groundLockable'] as bool? ?? false,
      surface: surfaceFromString(map['surface'] as String?),
      flat: map['flat'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'minDisplacementCc': minDisplacementCc,
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
  });

  /// 予約が必要かどうか。JMPSAデータでは予約制の施設名が「【予約制：◯◯】」で
  /// 始まるため、名称から判定する(akippa・特P・いつでもニリーン等)。
  bool get requiresReservation => name.contains('予約制');

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
    );
  }
}
