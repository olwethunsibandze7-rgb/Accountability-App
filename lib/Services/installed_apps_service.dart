import 'package:flutter/services.dart';

class InstalledAppsService {
  static const MethodChannel _channel =
      MethodChannel('achievr/installed_apps');

  Future<List<Map<String, String>>> getLaunchableApps() async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'getLaunchableApps',
    );

    if (result == null) return [];

    return result
        .whereType<Map>()
        .map(
          (item) => {
            'app_label': (item['app_label'] ?? '').toString(),
            'package_name': (item['package_name'] ?? '').toString(),
          },
        )
        .where(
          (item) =>
              item['app_label']!.trim().isNotEmpty &&
              item['package_name']!.trim().isNotEmpty,
        )
        .toList();
  }
}