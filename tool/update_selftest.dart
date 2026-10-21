// CI entry point (`flutter build <desktop> -t tool/update_selftest.dart`): installs the latest published
// release over this build through the same code as the "Check for updates" button, without the dialogs.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:photokeeper/update.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await installRelease(await latestTag(), ValueNotifier(null));
  } catch (e) {
    stderr.writeln('self-update failed: $e');
    exit(1);
  }
}
