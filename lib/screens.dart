// The five screens from mockups/: start, scanning, review grid, one-by-one, summary. One layout each;
// phones and desktops differ only where the input does (folder vs gallery, keys vs swipes).
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photokeeper_core/photokeeper_core.dart' show signalNames;

import 'session.dart';
import 'source.dart';

const keepGreen = Color(0xFF2E9E5B);
const deleteCoral = Color(0xFFE5574B);
const surface = Color(0xFFF7F7F5);

String fmtBytes(int b) =>
    b >= 1 << 30 ? '${(b / (1 << 30)).toStringAsFixed(1)} GB' : '${(b / (1 << 20)).toStringAsFixed(0)} MB';

class Root extends StatelessWidget {
  const Root(this.session, {super.key});
  final Session session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => switch (session.stage) {
      Stage.start => StartScreen(session),
      Stage.scanning => ScanningScreen(session),
      Stage.review => ReviewScreen(session),
      Stage.done => SummaryScreen(session),
    },
  );
}

// ---- 1. start ----

class StartScreen extends StatelessWidget {
  const StartScreen(this.session, {super.key});
  final Session session;

  Future<void> _go() async {
    final gallery = galleryIfMobile();
    if (gallery != null) return session.start(gallery);
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Folder to scan');
    if (dir != null) await session.start(FolderSource(Directory(dir)));
  }

  @override
  Widget build(BuildContext context) {
    final mobile = galleryIfMobile() != null;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('PhotoKeeper', style: text.labelLarge, textAlign: TextAlign.center),
                const SizedBox(height: 48),
                const Icon(Icons.photo_library_outlined, size: 72),
                const SizedBox(height: 24),
                Text('Find the junk in your gallery', style: text.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Screenshots, documents, memes. Runs on this device, nothing leaves it.',
                  style: text.bodyLarge?.copyWith(color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                FilledButton(
                  onPressed: _go,
                  style: FilledButton.styleFrom(backgroundColor: Colors.black87, padding: const EdgeInsets.all(20)),
                  child: Text(mobile ? 'Scan my photos' : 'Choose folder…'),
                ),
                const SizedBox(height: 12),
                Text(
                  session.error ??
                      (mobile
                          ? 'Needs photo access. You confirm every deletion.'
                          : 'Scans recursively. Nothing is deleted without your confirmation.'),
                  style: text.bodySmall?.copyWith(color: session.error == null ? Colors.black45 : deleteCoral),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- shared grid cell ----

class Cell extends StatelessWidget {
  const Cell(this.photo, {super.key, this.badge, this.onTap, this.onLongPress});
  final Photo photo;
  final Widget? badge;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final px = (160 * MediaQuery.devicePixelRatioOf(context)).round();
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            photo.image(px),
            if (badge != null) Positioned(top: 2, right: 2, child: badge!),
          ],
        ),
      ),
    );
  }
}

const _grid = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 150,
  mainAxisSpacing: 6,
  crossAxisSpacing: 6,
);

Widget dot(Color c) => Container(
  width: 12,
  height: 12,
  decoration: BoxDecoration(
    color: c,
    shape: BoxShape.circle,
    border: Border.all(color: Colors.white, width: 2),
  ),
);

// ---- 2. scanning ----

class ScanningScreen extends StatelessWidget {
  const ScanningScreen(this.session, {super.key});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final total = s.photos.length;
    final ms = s.done == 0 ? 0.0 : s.clock.elapsedMilliseconds / s.done;
    final left = ((total - s.done) * ms / 1000).ceil();
    final stats = total == 0
        ? 'Listing photos…'
        : '${s.done} of $total photos  ·  ${ms.toStringAsFixed(0)} ms/photo  ·  about ${left}s left';
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: total == 0 ? null : s.done / total,
                      color: Colors.black87,
                      backgroundColor: const Color(0xFFE8E8E4),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(stats),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('Keep ${s.keeps.length - s.suggested}', style: const TextStyle(color: keepGreen)),
                  const SizedBox(width: 16),
                  Text('Delete ${s.suggested}', style: const TextStyle(color: deleteCoral)),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: _grid,
                itemCount: total,
                itemBuilder: (_, i) => Cell(
                  s.photos[i],
                  badge: s.features[i] == null ? null : dot(s.verdictDelete(i) ? deleteCoral : keepGreen),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Preview(s.photos[i]))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Look-only view while the scan runs; deciding waits for the review screen, where every photo has a verdict.
class Preview extends StatelessWidget {
  const Preview(this.photo, {super.key});
  final Photo photo;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(backgroundColor: surface),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox.expand(
          child: photo.image((1200 * MediaQuery.devicePixelRatioOf(context)).round(), fit: BoxFit.contain),
        ),
      ),
    ),
  );
}

// ---- 3. review grid ----

class ReviewScreen extends StatefulWidget {
  const ReviewScreen(this.session, {super.key});
  final Session session;
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  Filter filter = Filter.delete;

  Future<void> _delete() async {
    final n = widget.session.selected.length;
    final mobile = galleryIfMobile() != null; // the gallery shows its own confirmation
    final ok =
        mobile ||
        await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text('Move $n photos to photokeeper-trash?'),
                content: const Text('A folder next to your photos. Nothing is permanently deleted.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    style: FilledButton.styleFrom(backgroundColor: deleteCoral),
                    child: const Text('Move'),
                  ),
                ],
              ),
            ) ==
            true;
    if (ok) await widget.session.deleteSelected();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final shown = s.indices(filter);
    final mobile = galleryIfMobile() != null;
    final bytes = s.selected.fold(0, (sum, i) => sum + s.photos[i].bytes);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: surface,
        title: Text('Suggested delete · ${s.suggested} photos${bytes > 0 ? ' · ${fmtBytes(bytes)}' : ''}'),
        actions: [TextButton(onPressed: s.reset, child: const Text('Start over'))],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final f in Filter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${f.name[0].toUpperCase() + f.name.substring(1)} ${s.indices(f).length}'),
                      selected: filter == f,
                      onSelected: (_) => setState(() => filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: _grid,
              itemCount: shown.length,
              itemBuilder: (_, k) {
                final i = shown[k];
                final on = s.selected.contains(i);
                return Cell(
                  s.photos[i],
                  badge: IconButton(
                    onPressed: () => s.toggle(i),
                    tooltip: on ? 'Unselect' : 'Select',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      on ? Icons.check_circle : Icons.circle_outlined,
                      color: on ? deleteCoral : Colors.white,
                      size: 22,
                      shadows: const [Shadow(blurRadius: 4)],
                    ),
                  ),
                  onTap: () =>
                      Navigator.push(context, MaterialPageRoute(builder: (_) => SingleReview(s, shown, start: k))),
                  onLongPress: () {
                    HapticFeedback.selectionClick();
                    s.toggle(i);
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('${s.selected.length} selected', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: shown.isEmpty
                        ? null
                        : () => Navigator.push(context, MaterialPageRoute(builder: (_) => SingleReview(s, shown))),
                    child: const Text('One by one'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: s.selected.isEmpty ? null : _delete,
                    style: FilledButton.styleFrom(
                      backgroundColor: deleteCoral,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                    ),
                    child: Text(mobile ? 'Delete ${s.selected.length}' : 'Move to Trash'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- 4. one by one: swipe or K/D ----

class SingleReview extends StatefulWidget {
  const SingleReview(this.session, this.indices, {super.key, this.start = 0});
  final Session session;
  final List<int> indices;
  final int start;
  @override
  State<SingleReview> createState() => _SingleReviewState();
}

class _SingleReviewState extends State<SingleReview> {
  late int pos = widget.start;
  final undo = <(int, bool)>[]; // (position, was selected)

  void _decide(bool delete) {
    final i = widget.indices[pos];
    undo.add((pos, widget.session.selected.contains(i)));
    widget.session.toggle(i, delete: delete);
    if (pos + 1 == widget.indices.length) return Navigator.pop(context);
    setState(() => pos++);
  }

  void _undo() {
    if (undo.isEmpty) return;
    final (p, was) = undo.removeLast();
    widget.session.toggle(widget.indices[p], delete: was);
    setState(() => pos = p);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final i = widget.indices[pos];
    final f = s.features[i]!;
    final why = reason(f);
    final px = (1200 * MediaQuery.devicePixelRatioOf(context)).round();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK): () => _decide(false),
        const SingleActivator(LogicalKeyboardKey.keyD): () => _decide(true),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _decide(false),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _decide(true),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: surface,
            title: Text('${pos + 1} of ${widget.indices.length}'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: Text('Suggested: ${s.verdictDelete(i) ? 'delete' : 'keep'}')),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Dismissible(
                      key: ValueKey(i),
                      direction: DismissDirection.horizontal,
                      onDismissed: (d) => _decide(d == DismissDirection.endToStart),
                      background: const _Swipe(keepGreen, Icons.check, Alignment.centerLeft),
                      secondaryBackground: const _Swipe(deleteCoral, Icons.close, Alignment.centerRight),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox.expand(child: s.photos[i].image(px, fit: BoxFit.contain)),
                      ),
                    ),
                  ),
                ),
                Text(
                  '${s.verdictDelete(i) ? 'Looks like a $why' : 'Looks like a photo'}'
                  '  ·  keep score ${keepScore(f).toStringAsFixed(2)}, keeps at $keepThreshold'
                  '${edgeVeto(f) ? ', but straight edges force delete' : ''}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(children: [for (var k = 0; k < f.length; k++) _Score(k, f[k], keepLikeness(f)[k])]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _decide(false),
                          icon: const Icon(Icons.check, color: keepGreen),
                          label: const Text('Keep  K'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.all(18),
                            foregroundColor: keepGreen,
                          ),
                        ),
                      ),
                      IconButton(onPressed: undo.isEmpty ? null : _undo, icon: const Icon(Icons.undo), tooltip: 'Undo'),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _decide(true),
                          icon: const Icon(Icons.close),
                          label: const Text('Delete  D'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.all(18),
                            backgroundColor: deleteCoral,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One signal as the category it argues for: faces argue keep (green), the rest argue delete (coral).
class _Score extends StatelessWidget {
  const _Score(this.k, this.raw, this.keepLike);
  final int k;
  final double raw, keepLike;

  static const _labels = [
    'Photo (faces)',
    'Document (flat colours)',
    'Screenshot (straight edges)',
    'Document (blown-out)',
    'Text',
  ];

  @override
  Widget build(BuildContext context) {
    final value = k == 0 ? keepLike : 1 - keepLike;
    return Tooltip(
      message: '${signalNames[k]} = ${raw.toStringAsFixed(3)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 190, child: Text(_labels[k])),
            Expanded(
              child: LinearProgressIndicator(
                value: value,
                color: k == 0 ? keepGreen : deleteCoral,
                backgroundColor: const Color(0xFFE8E8E4),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            SizedBox(width: 48, child: Text('${(value * 100).round()}%', textAlign: TextAlign.right)),
          ],
        ),
      ),
    );
  }
}

class _Swipe extends StatelessWidget {
  const _Swipe(this.color, this.icon, this.align);
  final Color color;
  final IconData icon;
  final Alignment align;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(8)),
    alignment: align,
    padding: const EdgeInsets.all(32),
    child: Icon(icon, color: color, size: 48),
  );
}

// ---- 5. summary ----

class SummaryScreen extends StatelessWidget {
  const SummaryScreen(this.session, {super.key});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final text = Theme.of(context).textTheme;
    final mobile = galleryIfMobile() != null;
    final deletedIdx = {for (final p in s.deleted) p.id};
    final byReason = <String, int>{};
    for (final i in s.keeps.keys) {
      if (deletedIdx.contains(s.photos[i].id)) byReason.update(reason(s.features[i]!), (n) => n + 1, ifAbsent: () => 1);
    }
    final keptAfterReview = s.indices(Filter.delete).where((i) => !s.selected.contains(i)).length;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.check_circle_outline, color: keepGreen, size: 72),
                const SizedBox(height: 24),
                Text(
                  s.freedBytes > 0
                      ? '${fmtBytes(s.freedBytes)} freed'
                      : '${s.deleted.length} photos ${mobile ? 'deleted' : 'moved to trash'}',
                  style: text.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '${s.deleted.length} deleted · $keptAfterReview kept after review · ${s.photos.length} scanned in ${(s.clock.elapsedMilliseconds / 1000).toStringAsFixed(0)} s',
                  style: text.bodyLarge?.copyWith(color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                for (final e in byReason.entries)
                  ListTile(
                    title: Text(e.key[0].toUpperCase() + e.key.substring(1)),
                    trailing: Text('${e.value}', style: const TextStyle(color: keepGreen, fontSize: 16)),
                  ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: s.reset,
                  style: FilledButton.styleFrom(backgroundColor: Colors.black87, padding: const EdgeInsets.all(20)),
                  child: Text(mobile ? 'Done' : 'Scan another folder'),
                ),
                const SizedBox(height: 12),
                Text(
                  mobile
                      ? 'Recently Deleted keeps them for 30 days.'
                      : 'Restore anything from the photokeeper-trash folder next to your photos.',
                  style: text.bodySmall?.copyWith(color: Colors.black45),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
