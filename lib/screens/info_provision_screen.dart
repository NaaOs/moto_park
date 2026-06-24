import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// 「管理会社からの情報提供」案内ページ。
///
/// 駐輪場の管理会社・運営者が、新規掲載や情報提供を行うための窓口を案内する。
/// 掲載・情報提供は運営窓口が受け付けている。
class InfoProvisionScreen extends StatelessWidget {
  const InfoProvisionScreen({super.key});

  // 「バイク駐車場の掲載依頼」ページ。
  static const _registerUrl = 'https://www.jmpsa.or.jp/society/parking/register.html';
  // 「掲載依頼・掲載内容の変更」フォーム。
  static const _contactUrl = 'https://www.jmpsa.or.jp/contact/form/index_18.html';

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('管理会社からの情報提供')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.campaign_outlined, color: AppTheme.accent, size: 34),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'バイク駐輪場を運営されている管理会社・事業者の皆さまへ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'MotoPark に掲載している駐輪場情報は、提携する情報元の'
            '全国バイク駐車場案内をもとにしています。\n\n'
            '新しいバイク駐輪場の掲載や、運営する駐輪場の情報提供をご希望の場合は、'
            '運営窓口より受け付けています。下記からお手続きください。',
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 24),

          _ActionCard(
            icon: Icons.add_business_outlined,
            title: '駐輪場の掲載を依頼する',
            subtitle: '新規にバイク駐輪場を掲載したい管理会社・事業者の方はこちら',
            onTap: () => _open(_registerUrl),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.mail_outline,
            title: 'お問い合わせ・情報提供フォーム',
            subtitle: '掲載内容の追加・変更のご相談はこちら',
            onTap: () => _open(_contactUrl),
          ),

          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF7F0),
              borderRadius: BorderRadius.circular(12),
              border: const Border(left: BorderSide(color: Color(0xFF3A9D5D), width: 4)),
            ),
            child: const Text(
              'ご提供いただいた情報は、運営側の確認のうえで掲載されます。'
              '掲載までにお時間をいただく場合があります。',
              style: TextStyle(height: 1.5, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 30, color: AppTheme.accent),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.open_in_new),
        onTap: onTap,
      ),
    );
  }
}
