// End to end on the real core, against the CLI repo's eval_data. Needs libphotokeeper_core.so on the loader path:
//   cmake -S core/src -B /tmp/pkcore && cmake --build /tmp/pkcore -j6 && LD_LIBRARY_PATH=/tmp/pkcore flutter test
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photokeeper/session.dart';
import 'package:photokeeper/source.dart';
import 'package:photokeeper_core/photokeeper_core.dart' as core;

void main() {
  test('folder scan: verdicts match the CLI, junk is undecodable, delete moves to trash', () async {
    final cli = Directory('${Directory.current.path}/../photokeeper');
    final root = Directory.systemTemp.createTempSync('pk');
    for (final f in Directory('${cli.path}/eval_data').listSync(recursive: true).whereType<File>()) {
      f.copySync('${root.path}/${f.uri.pathSegments.last}'); // 6 decodable + 2 HEIC
    }
    File('${root.path}/junk.jpg').writeAsStringSync('not an image');
    core.init('${cli.path}/models');

    final s = Session();
    await s.start(FolderSource(root));
    expect(s.stage, Stage.review);
    expect(s.photos.length, 7, reason: 'HEIC is filtered by extension, junk.jpg is listed');
    int at(String name) => s.photos.indexWhere((p) => p.id.endsWith(name));
    expect(s.keeps[at('5_yes.jpeg')], false); // same verdicts as `photokeeper eval_data`
    expect(s.keeps[at('7_yes.jpeg')], false);
    expect(s.keeps[at('3_no.png')], true);
    expect(s.features[at('junk.jpg')], isNull);
    expect(s.selected.length, 4);
    expect(s.indices(Filter.delete).length, 4);
    expect(s.indices(Filter.keep).length, 2);
    const shot = [1.0, 0.3, 0.7, 0.0, 0.0]; // textless screenshot: the score alone would keep it
    for (final f in [shot, for (final i in s.keeps.keys) s.features[i]!]) {
      expect(
        keepScore(f) >= keepThreshold && !edgeVeto(f),
        core.keep(f),
        reason: 'preview scores drifted from pipeline.cpp',
      );
    }
    expect(edgeVeto(shot) && keepScore(shot) >= keepThreshold, true);

    s.toggle(at('5_yes.jpeg')); // user rescues one
    await s.deleteSelected();
    expect(s.stage, Stage.done);
    expect(s.deleted.length, 3);
    expect(Directory('${root.path}/${FolderSource.trashName}').listSync().length, 3);
    expect(root.listSync().whereType<File>().length, 9 - 3);
    root.deleteSync(recursive: true);
  });
}
