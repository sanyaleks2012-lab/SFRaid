import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

Future<bool> requestStoragePermission() async {
  if (!Platform.isAndroid) return true;

  try {
    var status = await Permission.manageExternalStorage.status;

    if (status.isGranted) return true;

    status = await Permission.manageExternalStorage.request();

    return status.isGranted;
  } catch (_) {
    return false;
  }
}
