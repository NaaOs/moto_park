import 'package:url_launcher/url_launcher.dart';

/// 「現在地からのワンタップ経路案内」: 端末の地図/ナビアプリへ連携する。
class NavigationLauncher {
  Future<bool> launchTo({required double latitude, required double longitude, String? label}) async {
    final query = Uri.encodeComponent(label ?? '$latitude,$longitude');
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude&destination_place_id=&travelmode=driving&dir_action=navigate&q=$query',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
