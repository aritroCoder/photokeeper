// dart:ffi bindings for pipeline_c/pk.h in the photokeeper CLI repo. Four functions, written by hand;
// ffigen would need libclang on every dev machine for the same fifteen lines.
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const int featureCount = 5;
const List<String> signalNames = ['faces', 'palette_flatness', 'axis_edge_ratio', 'clipped', 'text_area_ratio'];

final DynamicLibrary _lib = () {
  const name = 'photokeeper_core';
  if (Platform.isMacOS || Platform.isIOS) return DynamicLibrary.open('$name.framework/$name');
  if (Platform.isWindows) return DynamicLibrary.open('$name.dll');
  return DynamicLibrary.open('lib$name.so');
}();

final _init = _lib.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('pk_init');
final _analyzePath = _lib
    .lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Double>), int Function(Pointer<Utf8>, Pointer<Double>)>(
      'pk_analyze_path',
    );
final _analyzeEncoded = _lib
    .lookupFunction<
      Int32 Function(Pointer<Uint8>, Size, Pointer<Double>),
      int Function(Pointer<Uint8>, int, Pointer<Double>)
    >('pk_analyze_encoded');
final _keep = _lib.lookupFunction<Int32 Function(Pointer<Double>), int Function(Pointer<Double>)>('pk_keep');

/// Point the core at the directory holding the two ONNX models. Process-wide; call once before any analyze.
void init(String modelsDir) => using((arena) => _init(modelsDir.toNativeUtf8(allocator: arena)));

/// Features in [signalNames] order, or null if the file cannot be decoded. Blocks ~10 ms; call from an isolate.
List<double>? analyzePath(String path) => using((arena) {
  final out = arena<Double>(featureCount);
  return _analyzePath(path.toNativeUtf8(allocator: arena), out) == 0 ? out.asTypedList(featureCount).toList() : null;
});

/// Same for encoded (JPEG/PNG/...) bytes already in memory, e.g. a gallery thumbnail.
List<double>? analyzeBytes(Uint8List bytes) => using((arena) {
  final buf = arena<Uint8>(bytes.length)..asTypedList(bytes.length).setAll(0, bytes);
  final out = arena<Double>(featureCount);
  return _analyzeEncoded(buf, bytes.length, out) == 0 ? out.asTypedList(featureCount).toList() : null;
});

bool keep(List<double> features) => using((arena) {
  final f = arena<Double>(featureCount)..asTypedList(featureCount).setAll(0, features);
  return _keep(f) == 1;
});
