// One scan from start to summary: lists photos, fans them out to worker isolates that call the core,
// keeps the verdicts and the user's overrides, and performs the delete.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:photokeeper_core/photokeeper_core.dart' as core;

import 'source.dart';

enum Stage { start, scanning, review, done }

enum Filter { delete, keep }

/// pipeline.cpp's vote mirrored for the preview: per signal its keep-likeness ramp and weight.
/// session_test fails if this drifts from the core's verdict.
final List<(double Function(double), double)> _vote = [
  ((v) => min(v, 1.0), 0.03),
  ((v) => ((0.9 - v) / 0.4).clamp(0.0, 1.0), 0.10),
  ((v) => ((0.6 - v) / 0.4).clamp(0.0, 1.0), 0.19),
  ((v) => (1 - v / 0.3).clamp(0.0, 1.0), 0.13),
  ((v) => (1 - v / 0.05).clamp(0.0, 1.0), 0.55),
];
const keepThreshold = 0.78;

/// Screenshot-like edges mark a photo for delete whatever its score, as in the core.
bool edgeVeto(List<double> f) => f[2] >= 0.6;

/// Keep-likeness in [0, 1] per signal; a failed (NaN) signal is neutral, as in the core.
List<double> keepLikeness(List<double> f) => [for (var k = 0; k < f.length; k++) f[k].isNaN ? 0.5 : _vote[k].$1(f[k])];

double keepScore(List<double> f) {
  final l = keepLikeness(f);
  return [for (var k = 0; k < l.length; k++) _vote[k].$2 * l[k]].fold(0.0, (a, b) => a + b);
}

/// Which of the core's ramps drove a delete verdict; thresholds are where pipeline.cpp's ramps saturate.
/// shortcut: first saturated signal wins, good enough for a label; the verdict itself is the core's weighted vote
String reason(List<double> f) {
  if (f[2] >= 0.6) return 'screenshot'; // axis_edge_ratio
  if (f[4] >= 0.05) return 'text'; // text_area_ratio
  if (f[1] >= 0.9 || f[3] >= 0.3) return 'document'; // palette_flatness, clipped
  return 'low score';
}

/// Nearest-rank percentile, [p] in (0, 1]; NaN when [xs] is empty.
double percentile(List<double> xs, double p) {
  if (xs.isEmpty) return double.nan;
  final s = [...xs]..sort();
  return s[(p * s.length).ceil() - 1];
}

class Session extends ChangeNotifier {
  Stage stage = Stage.start;
  String? error;
  PhotoSource? source;
  List<Photo> photos = [];
  final Map<int, List<double>?> features = {}; // index -> features, null when undecodable
  final Map<int, bool> keeps = {}; // the core's verdict, decodable photos only
  final Set<int> selected = {}; // indices to delete; seeded from the verdicts, then the user's
  final Stopwatch clock = Stopwatch();
  List<Photo> deleted = [];
  int workers = 0;
  final List<double> coreMs = []; // per photo the core saw: time inside its analyze call, decode included
  int rssBefore = 0, rssPeak = 0; // whole process, bytes

  int get done => features.length;
  bool verdictDelete(int i) => keeps[i] == false;
  int get suggested => keeps.values.where((k) => !k).length;
  int get freedBytes => deleted.fold(0, (sum, p) => sum + p.bytes);

  List<int> indices(Filter f) => [
    for (final i in keeps.keys)
      if (verdictDelete(i) == (f == Filter.delete)) i,
  ]..sort();

  Future<void> start(PhotoSource s) async {
    source = s;
    stage = Stage.scanning;
    error = null;
    notifyListeners();
    try {
      photos = await s.list();
    } catch (e) {
      error = '$e';
      stage = Stage.start;
      notifyListeners();
      return;
    }
    notifyListeners();
    coreMs.clear();
    rssBefore = rssPeak = ProcessInfo.currentRss;
    clock
      ..reset()
      ..start();
    var next = 0;
    workers = Platform.numberOfProcessors.clamp(1, 6); // faces/text detectors serialise behind locks anyway
    await Future.wait([for (var w = 0; w < workers; w++) _worker(() => next < photos.length ? next++ : null)]);
    clock.stop();
    stage = Stage.review;
    notifyListeners();
  }

  Future<void> _worker(int? Function() take) async {
    final rx = ReceivePort();
    final results = StreamIterator(rx);
    await Isolate.spawn(_analyze, rx.sendPort);
    await results.moveNext();
    final tx = results.current as SendPort;
    for (var i = take(); i != null; i = take()) {
      final payload = await photos[i].payload();
      List<double>? f;
      if (payload != null) {
        tx.send(payload);
        await results.moveNext();
        final (r, ms) = results.current as (List<double>?, double);
        f = r;
        coreMs.add(ms);
        // shortcut: sampled once per photo, so a spike inside one analyze call is missed; read the core's own peak if that matters
        rssPeak = max(rssPeak, ProcessInfo.currentRss);
      }
      features[i] = f;
      if (f != null && !(keeps[i] = core.keep(f))) selected.add(i);
      notifyListeners();
    }
    tx.send(null);
    rx.close();
  }

  // Runs in a worker isolate; the core's model and mutexes are process-wide so every isolate shares them.
  static void _analyze(SendPort out) {
    final rx = ReceivePort();
    out.send(rx.sendPort);
    rx.listen((payload) {
      if (payload == null) return rx.close();
      final sw = Stopwatch()..start();
      final f = payload is String ? core.analyzePath(payload) : core.analyzeBytes(payload as Uint8List);
      out.send((f, sw.elapsedMicroseconds / 1000));
    });
  }

  void toggle(int i, {bool? delete}) {
    (delete ?? !selected.contains(i)) ? selected.add(i) : selected.remove(i);
    notifyListeners();
  }

  Future<void> deleteSelected() async {
    deleted = await source!.delete([for (final i in selected) photos[i]]);
    stage = Stage.done;
    notifyListeners();
  }

  void reset() {
    stage = Stage.start;
    photos = [];
    features.clear();
    keeps.clear();
    selected.clear();
    deleted = [];
    notifyListeners();
  }
}
