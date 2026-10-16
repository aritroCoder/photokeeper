import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photokeeper_core/photokeeper_core.dart' as core;

import 'screens.dart';
import 'session.dart';

const _models = ['face_detection_yunet_2023mar.onnx', 'text_detection_en_ppocrv3_2023may.onnx'];

/// The core wants the ONNX files on disk; Flutter assets are not files on Android, so copy them out once.
Future<String> _unpackModels() async {
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/models');
  for (final name in _models) {
    final f = File('${dir.path}/$name');
    if (!f.existsSync()) {
      f.createSync(recursive: true);
      await f.writeAsBytes((await rootBundle.load('assets/models/$name')).buffer.asUint8List());
    }
  }
  return dir.path;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  core.init(await _unpackModels());
  runApp(
    MaterialApp(
      title: 'PhotoKeeper',
      theme: ThemeData(colorSchemeSeed: Colors.black, scaffoldBackgroundColor: surface),
      home: Root(Session()),
    ),
  );
}
