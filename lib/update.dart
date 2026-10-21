// Self-update from the latest GitHub Release. Each platform installs the asset CI publishes for it:
// Android hands the APK to the system installer, Windows runs the Inno Setup installer silently,
// Linux and macOS swap the app folder in place and relaunch. iOS sideloads can't install anything,
// so they only get the link.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

// The website, not api.github.com: the API allows 60 anonymous requests an hour per IP, which CI runners
// and users behind a shared address run out of.
const _repo = 'https://github.com/aritroCoder/photokeeper';
const _android = MethodChannel('photokeeper/update');

String? get _assetName => switch (Platform.operatingSystem) {
  'android' => 'photokeeper-android-arm64.apk',
  'windows' => 'photokeeper-windows-x64-setup.exe',
  'macos' => 'photokeeper-macos-arm64.zip',
  'linux' => 'photokeeper-linux-x64.tar.gz',
  _ => null,
};

/// Whether release [tag] (`v0.0.2` or `0.0.2`) is newer than the running [version] (`0.0.1+1`).
bool isNewer(String tag, String version) {
  List<int> parts(String v) =>
      v.replaceFirst('v', '').split(RegExp('[+-]')).first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final a = parts(tag), b = parts(version);
  for (var i = 0; i < 3; i++) {
    final d = (i < a.length ? a[i] : 0) - (i < b.length ? b[i] : 0);
    if (d != 0) return d > 0;
  }
  return false;
}

final _http = HttpClient()..userAgent = 'photokeeper';

Future<HttpClientResponse> _get(String url) async {
  final res = await (await _http.getUrl(Uri.parse(url))).close(); // follows GitHub's redirect to the asset CDN
  if (res.statusCode != 200) throw HttpException('GitHub answered ${res.statusCode}', uri: Uri.parse(url));
  return res;
}

Future<File> _download(String tag, ValueNotifier<double?> progress) async {
  final dir = (await getTemporaryDirectory())..createSync(recursive: true); // unsandboxed macOS: may not exist yet
  final file = File('${dir.path}/$_assetName');
  final res = await _get('$_repo/releases/download/$tag/$_assetName');
  final size = res.contentLength;
  final sink = file.openWrite();
  var got = 0;
  try {
    await for (final chunk in res) {
      sink.add(chunk);
      if (size > 0) progress.value = (got += chunk.length) / size;
    }
  } finally {
    await sink.close();
  }
  if (size > 0 && got != size) throw HttpException('Download stopped at $got of $size bytes');
  return file;
}

Future<Never> _install(File file) async {
  if (Platform.isWindows) {
    // Same AppId, so Setup reuses the existing install folder; /RELAUNCH=1 makes it start the app again.
    await Process.start(file.path, [
      '/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/RELAUNCH=1', //
    ], mode: ProcessStartMode.detached);
    exit(0);
  }
  // POSIX lets a running app's folder be renamed, so: unpack next to it, swap, relaunch.
  final exe = File(Platform.resolvedExecutable);
  final app = Platform.isMacOS ? exe.parent.parent.parent : exe.parent; // photokeeper.app, or the Linux bundle
  if (app.path.contains('/AppTranslocation/')) {
    throw const FileSystemException('macOS is running PhotoKeeper from a read-only copy. Move it to Applications first.');
  }
  final staging = Directory('${app.path}.update');
  final old = Directory('${app.path}.old');
  for (final d in [staging, old]) {
    if (d.existsSync()) d.deleteSync(recursive: true);
  }
  staging.createSync();
  final r = Platform.isMacOS
      ? await Process.run('ditto', ['-x', '-k', file.path, staging.path])
      : await Process.run('tar', ['-xzf', file.path, '-C', staging.path]);
  if (r.exitCode != 0) throw ProcessException('unpack', [file.path], '${r.stderr}', r.exitCode);
  app.renameSync(old.path);
  try {
    Directory('${staging.path}/${Platform.isMacOS ? 'photokeeper.app' : 'bundle'}').renameSync(app.path);
  } catch (_) {
    old.renameSync(app.path);
    rethrow;
  }
  old.deleteSync(recursive: true);
  staging.deleteSync(recursive: true);
  await (Platform.isMacOS
      ? Process.start('open', ['-n', app.path], mode: ProcessStartMode.detached) // -n: don't just refocus this one
      : Process.start('${app.path}/photokeeper', [], mode: ProcessStartMode.detached));
  exit(0);
}

/// The newest non-prerelease tag, from where `github.com/<repo>/releases/latest` redirects.
Future<String> latestTag() async {
  final res = await (await _http.getUrl(Uri.parse('$_repo/releases/latest'))..followRedirects = false).close();
  await res.drain<void>();
  final to = res.headers.value(HttpHeaders.locationHeader);
  if (!res.isRedirect || to == null) throw HttpException('GitHub answered ${res.statusCode}');
  return Uri.parse(to).pathSegments.last; // .../releases/tag/v0.0.2; just .../releases if none is published
}

/// Downloads and installs this platform's asset of release [tag]. Desktop quits here and comes back as
/// the new version; Android returns once the system installer has taken over.
Future<void> installRelease(String tag, ValueNotifier<double?> progress) async {
  final file = await _download(tag, progress);
  if (Platform.isAndroid) return _android.invokeMethod('install', file.path);
  await _install(file);
}

/// The "Check for updates" button: asks GitHub, offers the newer release, downloads and installs it.
Future<void> checkForUpdates(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String s) => messenger.showSnackBar(SnackBar(content: Text(s)));
  final String tag, version;
  try {
    version = (await PackageInfo.fromPlatform()).version;
    tag = await latestTag();
  } catch (e) {
    return say('Could not check for updates: $e');
  }
  if (!isNewer(tag, version)) return say('PhotoKeeper $version is the latest version.');
  if (!context.mounted) return;

  final url = '$_repo/releases/tag/$tag';
  final manual = _assetName == null;
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(manual ? 'Update PhotoKeeper manually' : 'PhotoKeeper $tag is available'),
      content: Text(
        manual
            ? 'PhotoKeeper $tag is out (you have $version), but iPhone apps installed outside the App Store '
                  'can\'t update themselves.\n\n'
                  'To update: download photokeeper-ios-unsigned.ipa from the release page below and install it '
                  'with AltStore or Sideloadly, the same way you installed PhotoKeeper the first time.\n\n$url'
            : 'You have $version. The update downloads from GitHub and PhotoKeeper restarts.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Later')),
        if (!manual)
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Update'))
        else
          FilledButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(c, false);
            },
            child: const Text('Copy link'),
          ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  final progress = ValueNotifier<double?>(null);
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: Text('Downloading $tag…'),
      content: ValueListenableBuilder(
        valueListenable: progress,
        builder: (_, v, _) => LinearProgressIndicator(value: v),
      ),
    ),
  );
  try {
    await installRelease(tag, progress);
    navigator.pop();
  } catch (e) {
    navigator.pop();
    say('Update failed: $e');
  }
}
