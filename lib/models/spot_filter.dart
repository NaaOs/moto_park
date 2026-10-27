import 'parking_spot.dart';

/// 詳細条件による絞り込み検索の条件セット。
/// 各フィールドが null / false の場合は「指定なし」を表す。
class SpotFilter {
  // あなたのバイクの排気量(cc)。指定すると、その排気量を受け入れる駐輪場のみ表示。
  final int? minDisplacementCc;
  final bool roofedOnly;
  final bool groundLockableOnly;
  final GroundSurface? surface;
  final bool flatOnly;
  // 予約の要否。null=指定なし / true=予約制のみ / false=予約不要のみ
  final bool? requiresReservation;
  // 施設の種類。null=指定なし / parking=駐輪場のみ / commercial=商業施設のみ
  final SpotSource? source;

  const SpotFilter({
    this.minDisplacementCc,
    this.roofedOnly = false,
    this.groundLockableOnly = false,
    this.surface,
    this.flatOnly = false,
    this.requiresReservation,
    this.source,
  });

  bool get isActive =>
      minDisplacementCc != null ||
      roofedOnly ||
      groundLockableOnly ||
      surface != null ||
      flatOnly ||
      requiresReservation != null ||
      source != null;

  int get activeCount => [
        minDisplacementCc != null,
        roofedOnly,
        groundLockableOnly,
        surface != null,
        flatOnly,
        requiresReservation != null,
        source != null,
      ].where((v) => v).length;

  bool matches(ParkingSpot spot) {
    if (minDisplacementCc != null && !spot.conditions.accepts(minDisplacementCc!)) {
      return false;
    }
    if (roofedOnly && !spot.conditions.roofed) return false;
    if (groundLockableOnly && !spot.conditions.groundLockable) return false;
    if (surface != null && spot.conditions.surface != surface) return false;
    if (flatOnly && !spot.conditions.flat) return false;
    if (requiresReservation != null && spot.requiresReservation != requiresReservation) {
      return false;
    }
    if (source != null && spot.source != source) return false;
    return true;
  }

  SpotFilter copyWith({
    int? minDisplacementCc,
    bool clearMinDisplacementCc = false,
    bool? roofedOnly,
    bool? groundLockableOnly,
    GroundSurface? surface,
    bool clearSurface = false,
    bool? flatOnly,
    bool? requiresReservation,
    bool clearRequiresReservation = false,
    SpotSource? source,
    bool clearSource = false,
  }) {
    return SpotFilter(
      minDisplacementCc: clearMinDisplacementCc ? null : (minDisplacementCc ?? this.minDisplacementCc),
      roofedOnly: roofedOnly ?? this.roofedOnly,
      groundLockableOnly: groundLockableOnly ?? this.groundLockableOnly,
      surface: clearSurface ? null : (surface ?? this.surface),
      flatOnly: flatOnly ?? this.flatOnly,
      requiresReservation:
          clearRequiresReservation ? null : (requiresReservation ?? this.requiresReservation),
      source: clearSource ? null : (source ?? this.source),
    );
  }
}
