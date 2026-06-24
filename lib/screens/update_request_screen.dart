import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import '../models/parking_spot.dart';
import '../theme/app_theme.dart';

/// 掲載情報の「更新・削除依頼」案内ページ。
///
/// 当アプリの駐輪場データは提携する情報元および各管理会社が
/// 掲載・運営している。情報の変更・閉鎖・削除の依頼は、原則として
/// 管理会社へ直接連絡するか、掲載内容変更フォームから行う。
class UpdateRequestScreen extends StatelessWidget {
  const UpdateRequestScreen({super.key, required this.spot});

  final ParkingSpot spot;

  // 「掲載依頼・掲載内容の変更」窓口。
  static const _changeFormUrl = 'https://www.jmpsa.or.jp/contact/form/index_18.html';

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final tel = spot.tel;
    final company = spot.managementCompany;

    return Scaffold(
      appBar: AppBar(title: const Text('更新・削除依頼')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Lead(name: spot.name),
          const SizedBox(height: 20),

          // ── 管理会社へ連絡 ──
          const _SectionTitle(icon: Icons.business_outlined, text: '① 管理会社へ連絡する'),
          const SizedBox(height: 8),
          const Text(
            '料金・営業時間・閉鎖などの最新情報は、駐輪場を運営する管理会社が把握しています。'
            'まずは管理会社へお問い合わせください。',
            style: TextStyle(height: 1.5),
          ),
          const SizedBox(height: 12),
          if (company != null)
            _DetailRow(icon: Icons.business_outlined, label: '管理会社', value: company),
          if (tel != null)
            _DetailRow(
              icon: Icons.call_outlined,
              label: 'TEL',
              value: tel,
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: '電話をかける',
                    icon: const Icon(Icons.call, color: AppTheme.accent),
                    onPressed: () => _open('tel:${tel.replaceAll(RegExp(r'[^0-9+]'), '')}'),
                  ),
                  IconButton(
                    tooltip: '番号をコピー',
                    icon: const Icon(Icons.copy, color: AppTheme.accent),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: tel));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('電話番号をコピーしました')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          if (company == null && tel == null)
            const Text(
              '※ この駐輪場には管理会社・電話番号の掲載がありません。'
              '下記の窓口からご依頼ください。',
              style: TextStyle(color: Colors.black54),
            ),

          const SizedBox(height: 24),
          // ── 運営窓口 ──
          const _SectionTitle(icon: Icons.mark_email_read_outlined, text: '② 運営窓口から依頼する'),
          const SizedBox(height: 8),
          const Text(
            '掲載内容の変更・駐輪場の削除(閉鎖)依頼は、「掲載依頼・掲載内容の変更」'
            'フォームから受け付けています。',
            style: TextStyle(height: 1.5),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppTheme.accent,
            ),
            onPressed: () => _open(_changeFormUrl),
            icon: const Icon(Icons.open_in_new),
            label: const Text('掲載内容の変更・削除を依頼する'),
          ),
          if (spot.infoUrl != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => _open(spot.infoUrl!),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('この駐輪場の掲載ページを開く'),
            ),
          ],

          const SizedBox(height: 24),
          const _Note(
            text: '予約制(akippa・特P 等)の駐輪場は、各予約サービスのサイトから'
                '情報の修正・解約を行ってください。',
          ),
        ],
      ),
    );
  }
}

class _Lead extends StatelessWidget {
  const _Lead({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          const Text(
            'この駐輪場の掲載情報に誤り・変更・閉鎖がある場合の依頼方法です。',
            style: TextStyle(color: Colors.black54, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.accent, size: 22),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black54),
          const SizedBox(width: 10),
          SizedBox(width: 76, child: Text(label, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 15))),
          ?trailing,
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E8),
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: Color(0xFFE8820C), width: 4)),
      ),
      child: Text(text, style: const TextStyle(height: 1.5, color: Colors.black87)),
    );
  }
}
