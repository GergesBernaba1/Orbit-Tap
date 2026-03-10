import 'dart:io';

import 'package:device_apps/device_apps.dart';

import '../models/installed_app.dart';

class PrivateAppsService {
  bool get isSupported => Platform.isAndroid;

  Future<List<InstalledAppModel>> fetchInstalledApps() async {
    if (!Platform.isAndroid) {
      return const [];
    }

    final applications = await DeviceApps.getInstalledApplications(
      includeAppIcons: false,
      includeSystemApps: false,
      onlyAppsWithLaunchIntent: true,
    );

    return applications
        .map(
          (application) => InstalledAppModel(
            appName: application.appName,
            packageName: application.packageName,
          ),
        )
        .toList()
      ..sort(
        (left, right) =>
            left.appName.toLowerCase().compareTo(right.appName.toLowerCase()),
      );
  }

  Future<bool> openApp(String packageName) async {
    if (!Platform.isAndroid) {
      return false;
    }

    return DeviceApps.openApp(packageName);
  }
}
