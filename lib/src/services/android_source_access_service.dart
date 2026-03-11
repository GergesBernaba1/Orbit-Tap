import 'dart:io';

import 'package:flutter/services.dart';

class AndroidSourceAccessService {
  static const MethodChannel _channel = MethodChannel('orbit_tap/media_source');

  Future<List<String>> deleteSourceIdentifiers(List<String> identifiers) async {
    if (!Platform.isAndroid || identifiers.isEmpty) {
      return identifiers;
    }

    try {
      final failed = await _channel.invokeMethod<List<dynamic>>(
        'deleteSourceUris',
        <String, dynamic>{
          'uris': identifiers,
        },
      );
      return (failed ?? const <dynamic>[]).whereType<String>().toList();
    } catch (_) {
      return identifiers;
    }
  }
}
