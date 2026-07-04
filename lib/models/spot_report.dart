/// ガセ情報・閉鎖済みスポットの通報理由。
enum ReportReason { closed, wrongInfo, notMotorcycleParking, other }

/// 通報の受付結果。UI側でメッセージを出し分ける。
/// hidden: 受け付けてこの端末では非表示にした / recorded: 記録のみ /
/// alreadyReported: 同一スポットへの通報済み(乱用防止のため1回まで)。
enum ReportOutcome { hidden, recorded, alreadyReported }

String reportReasonLabel(ReportReason reason) {
  switch (reason) {
    case ReportReason.closed:
      return '閉鎖されている';
    case ReportReason.wrongInfo:
      return '情報が間違っている';
    case ReportReason.notMotorcycleParking:
      return 'バイク駐輪場ではない';
    case ReportReason.other:
      return 'その他';
  }
}
