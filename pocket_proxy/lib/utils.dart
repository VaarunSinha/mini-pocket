import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copy an asset to application support dir so native libs can read by path.
Future<String> copyAssetToSupport(String assetPath) async {
  final dir = await getApplicationSupportDirectory();
  final name = p.basename(assetPath);
  final target = p.join(dir.path, name);
  final file = File(target);

  final data = await rootBundle.load(assetPath);
  if (!await file.exists() || file.lengthSync() != data.lengthInBytes) {
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }
  return target;
}
