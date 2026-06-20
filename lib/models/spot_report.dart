/// ガセ情報・閉鎖済みスポットの通報理由。
enum ReportReason { closed, wrongInfo, notMotorcycleParking, other }

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
