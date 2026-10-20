// Where photos come from. Desktop scans a folder and the core decodes files itself; phones go through the
// system gallery, which hands over already-decoded thumbnails (HEIC included) and owns the delete dialog.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

abstract class Photo {
  String get id;
  int get bytes; // on disk; 0 when the platform does not say (gallery)

  /// What the core analyzes: a file path (String) or encoded image bytes (Uint8List). null if unavailable.
  Future<Object?> payload();

  /// Thumbnail or preview; [px] is the long edge in physical pixels.
  Widget image(int px, {BoxFit fit = BoxFit.cover});
}

abstract class PhotoSource {
  Future<List<Photo>> list();

  /// Removes what it can and returns exactly those (the gallery dialog lets the user cancel).
  Future<List<Photo>> delete(List<Photo> photos);
}

PhotoSource? galleryIfMobile() => Platform.isAndroid || Platform.isIOS ? GallerySource() : null;

// ---- desktop: a folder ----

const _extensions = {'.jpg', '.jpeg', '.png', '.tif', '.tiff', '.bmp'}; // what the core's imgcodecs build decodes

class FolderSource implements PhotoSource {
  FolderSource(this.root);
  final Directory root;

  @override
  Future<List<Photo>> list() async {
    final found = <FilePhoto>[];
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File && _extensions.contains(_ext(e.path)) && !e.path.contains(trashName)) {
        found.add(FilePhoto(e, (await e.stat()).size));
      }
    }
    found.sort((a, b) => a.id.compareTo(b.id));
    return found;
  }

  static const trashName = 'photokeeper-trash';

  // shortcut: moves into <root>/photokeeper-trash instead of the OS recycle bin; swap for a trash plugin
  // (Windows SHFileOperation, NSFileManager.trashItem, XDG trash) once one exists for all three desktops
  @override
  Future<List<Photo>> delete(List<Photo> photos) async {
    final trash = Directory('${root.path}/$trashName')..createSync();
    final moved = <Photo>[];
    for (final p in photos.cast<FilePhoto>()) {
      var target = '${trash.path}/${p.file.uri.pathSegments.last}';
      for (var n = 1; File(target).existsSync(); n++) {
        target = '${trash.path}/$n-${p.file.uri.pathSegments.last}';
      }
      try {
        await p.file.rename(target);
        moved.add(p);
      } on FileSystemException {
        // read-only or cross-device: leave it, the summary counts only what moved
      }
    }
    return moved;
  }
}

String _ext(String path) {
  final dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot).toLowerCase();
}

class FilePhoto implements Photo {
  FilePhoto(this.file, this.bytes);
  final File file;
  @override
  final int bytes;
  @override
  String get id => file.path;
  @override
  Future<Object?> payload() async => file.path;
  @override
  Widget image(int px, {BoxFit fit = BoxFit.cover}) => Image.file(
    file,
    cacheWidth: px,
    fit: fit,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
  );
}

// ---- mobile: the system gallery ----

class GallerySource implements PhotoSource {
  @override
  Future<List<Photo>> list() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) throw StateError('Photo access denied. Allow it in system settings.');
    final count = await PhotoManager.getAssetCount(type: RequestType.image);
    final assets = count == 0
        ? <AssetEntity>[]
        : await PhotoManager.getAssetListRange(start: 0, end: count, type: RequestType.image);
    return [for (final a in assets) AssetPhoto(a)];
  }

  @override
  Future<List<Photo>> delete(List<Photo> photos) async {
    final gone = (await PhotoManager.editor.deleteWithIds([for (final p in photos) p.id])).toSet();
    return [
      for (final p in photos)
        if (gone.contains(p.id)) p,
    ];
  }
}

class AssetPhoto implements Photo {
  AssetPhoto(this.asset);
  final AssetEntity asset;
  @override
  String get id => asset.id;
  @override
  int get bytes => 0;

  // 640 so the core's INTER_AREA shrink to 320 does the final resample, same as the CLI
  @override
  Future<Object?> payload() => asset.thumbnailDataWithSize(const ThumbnailSize(640, 640), quality: 90);

  @override
  Widget image(int px, {BoxFit fit = BoxFit.cover}) => Image(
    image: GalleryThumb(asset, px),
    fit: fit,
    gaplessPlayback: true,
    frameBuilder: (_, child, frame, sync) => frame == null && !sync ? const ColoredBox(color: Color(0xFFE8E8E4)) : child,
    errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
  );
}

/// A gallery thumbnail behind Flutter's ImageCache: the scanning grid rebuilds once per analyzed photo, and
/// each rebuild must reuse the request already in flight instead of queuing another behind the scan's own.
class GalleryThumb extends ImageProvider<GalleryThumb> {
  const GalleryThumb(this.asset, this.px);
  final AssetEntity asset;
  final int px;

  @override
  Future<GalleryThumb> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(GalleryThumb key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _codec(decode), scale: 1);

  Future<ui.Codec> _codec(ImageDecoderCallback decode) async {
    final bytes = await asset.thumbnailDataWithSize(ThumbnailSize.square(px));
    if (bytes == null) throw StateError('no thumbnail for ${asset.id}');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is GalleryThumb && other.asset.id == asset.id && other.px == px;

  @override
  int get hashCode => Object.hash(asset.id, px);
}
