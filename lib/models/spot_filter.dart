import 'parking_spot.dart';

/// 詳細条件による絞り込み検索の条件セット。
/// 各フィールドが null / false の場合は「指定なし」を表す。
class SpotFilter {
  final int? minDisplacementCc; // 例: 125 を指定すると 125cc以上可 のスポットのみ
  final bool roofedOnly;
  final bool groundLockableOnly;
  final GroundSurface? surface;
  final bool flatOnly;
  // 予約の要否。null=指定なし / true=予約制のみ / false=予約不要のみ
  final bool? requiresReservation;

  const SpotFilter({
    this.minDisplacementCc,
    this.roofedOnly = false,
    this.groundLockableOnly = false,
    this.surface,
    this.flatOnly = false,
    this.requiresReservation,
  });

  bool get isActive =>
      minDisplacementCc != null ||
      roofedOnly ||
      groundLockableOnly ||
      surface != null ||
      flatOnly ||
      requiresReservation != null;

  int get activeCount => [
        minDisplacementCc != null,
        roofedOnly,
        groundLockableOnly,
        surface != null,
        flatOnly,
        requiresReservation != null,
      ].where((v) => v).length;

  bool matches(ParkingSpot spot) {
    if (minDisplacementCc != null && spot.conditions.minDisplacementCc > minDisplacementCc!) {
      return false;
    }
    if (roofedOnly && !spot.conditions.roofed) return false;
    if (groundLockableOnly && !spot.conditions.groundLockable) return false;
    if (surface != null && spot.conditions.surface != surface) return false;
    if (flatOnly && !spot.conditions.flat) return false;
    if (requiresReservation != null && spot.requiresReservation != requiresReservation) {
      return false;
    }
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
  }) {
    return SpotFilter(
      minDisplacementCc: clearMinDisplacementCc ? null : (minDisplacementCc ?? this.minDisplacementCc),
      roofedOnly: roofedOnly ?? this.roofedOnly,
      groundLockableOnly: groundLockableOnly ?? this.groundLockableOnly,
      surface: clearSurface ? null : (surface ?? this.surface),
      flatOnly: flatOnly ?? this.flatOnly,
      requiresReservation:
          clearRequiresReservation ? null : (requiresReservation ?? this.requiresReservation),
    );
  }
}
