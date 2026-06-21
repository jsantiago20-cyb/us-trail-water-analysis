import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'analysis/analyzer.dart';
import 'analysis/models.dart';
import 'analysis/report.dart';

/// How long to run before offering the user a "keep searching / stop" choice.
const _slowAfter = Duration(seconds: 60);

class ResultPage extends StatefulWidget {
  final String gpxText;
  final bool reverse;
  final DateTime date;
  final String title;

  const ResultPage({
    super.key,
    required this.gpxText,
    required this.reverse,
    required this.date,
    required this.title,
  });

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  AnalysisResult? _result;
  String _progress = 'Starting…';
  String? _error;
  bool _slow = false; // passed the 60s mark, still running
  Timer? _slowTimer;
  int _runId = 0; // guards against a stale run resolving after a retry

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  void _armSlowTimer() {
    _slowTimer?.cancel();
    _slowTimer = Timer(_slowAfter, () {
      if (mounted && _result == null && _error == null) {
        setState(() => _slow = true);
      }
    });
  }

  Future<void> _run() async {
    final myRun = ++_runId;
    setState(() {
      _result = null;
      _error = null;
      _slow = false;
      _progress = 'Starting…';
    });
    _armSlowTimer();
    try {
      final r = await analyze(
        widget.gpxText,
        reverse: widget.reverse,
        when: widget.date,
        web: kIsWeb,
        onProgress: (m) {
          if (mounted && myRun == _runId) setState(() => _progress = m);
        },
      );
      if (mounted && myRun == _runId) {
        _slowTimer?.cancel();
        setState(() {
          _result = r;
          _slow = false;
        });
      }
    } catch (e) {
      if (mounted && myRun == _runId) {
        _slowTimer?.cancel();
        setState(() => _error = e.toString());
      }
    }
  }

  // User chose to keep waiting on the in-flight run: hide the prompt and
  // re-arm the checkpoint. The analysis keeps running — no data is discarded.
  void _keepWaiting() {
    setState(() => _slow = false);
    _armSlowTimer();
  }

  void _share() {
    final r = _result;
    if (r == null) return;
    Share.share(renderMarkdown(r), subject: 'Water sources — ${r.routeName}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Water sources'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        actions: [
          if (_result != null)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Share report',
              onPressed: _share,
            ),
        ],
      ),
      body: _error != null
          ? _ErrorView(error: _error!, onRetry: _run)
          : _result == null
              ? _Loading(
                  progress: _progress,
                  slow: _slow,
                  onKeepWaiting: _keepWaiting,
                  onStop: () => Navigator.of(context).pop(),
                )
              : _ResultView(result: _result!, onRetry: _run),
    );
  }
}

class _Loading extends StatelessWidget {
  final String progress;
  final bool slow;
  final VoidCallback onKeepWaiting;
  final VoidCallback onStop;
  const _Loading({
    required this.progress,
    required this.slow,
    required this.onKeepWaiting,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(progress,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              slow
                  ? 'Still searching. A data source is taking longer than a '
                      'minute — it has not been cut off and is still running.'
                  : 'Querying USGS, NRCS, OpenStreetMap and NWS in parallel. '
                      'Usually about 5–15 seconds.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            if (slow) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onKeepWaiting,
                icon: const Icon(Icons.hourglass_bottom),
                label: const Text('Keep searching'),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: onStop, child: const Text('Stop')),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text('Analysis failed', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final AnalysisResult result;
  final VoidCallback onRetry;
  const _ResultView({required this.result, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = result;
    final crossingsFailed = r.incompleteSources.contains('stream crossings');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(r.routeName,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          '${r.direction} · ${r.totalDistanceMi} mi · ${r.analysisDate}',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        if (!r.isComplete) _IncompleteBanner(sources: r.incompleteSources, onRetry: onRetry),
        if (r.headline.mostReliable != null) _HeadlineCard(f: r.headline.mostReliable!, dir: r.direction),
        const SizedBox(height: 16),
        Text('Water sources in travel order',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (r.features.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(crossingsFailed
                  ? 'Stream-crossing data did not finish loading. Tap "Retry '
                      'incomplete data" above to try again.'
                  : 'No mapped stream crossings were found along this route.'),
            ),
          )
        else
          ...r.features.map((f) => _FeatureTile(f: f)),
        const SizedBox(height: 16),
        _ConditionsCard(c: r.conditions),
        const SizedBox(height: 16),
        Text(
          'Small foothills/backcountry streams are not potable without '
          'treatment. This judges presence of flow, not water quality.',
          style: theme.textTheme.bodySmall
              ?.copyWith(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

class _IncompleteBanner extends StatelessWidget {
  final List<String> sources;
  final VoidCallback onRetry;
  const _IncompleteBanner({required this.sources, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: const Color(0xFFFFF3E0),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_off, color: Color(0xFFE65100), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Some data didn’t finish loading',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'These sources timed out and aren’t included below: '
              '${sources.join(', ')}. The results may be incomplete.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry incomplete data'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _permColor(String perm) {
  switch (perm) {
    case 'perennial':
      return const Color(0xFF1565C0);
    case 'intermittent':
      return const Color(0xFF00897B);
    case 'ephemeral':
      return const Color(0xFF8D6E63);
    default:
      return const Color(0xFF757575);
  }
}

class _HeadlineCard extends StatelessWidget {
  final Feature f;
  final String dir;
  const _HeadlineCard({required this.f, required this.dir});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star, color: Color(0xFF1565C0)),
                const SizedBox(width: 8),
                Text('Most reliable water',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${f.trail ?? 'off-trail'} · $dir mile '
              '${f.mileLo.toStringAsFixed(2)}–${f.mileHi.toStringAsFixed(2)}'
              '${f.name != null ? ' · ${f.name}' : ''}',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 4),
            Text('${f.label} (${f.perm})',
                style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final Feature f;
  const _FeatureTile({required this.f});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _permColor(f.perm);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${f.trail ?? 'off-trail'} · mi ${f.mileRange}',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(f.perm,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: color)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(f.label, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (f.name != null) f.name!,
                      if (f.elevFt != null) '${f.elevFt} ft',
                      'conf: ${f.confidence}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConditionsCard extends StatelessWidget {
  final Conditions c;
  const _ConditionsCard({required this.c});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = <String>[];
    if (c.drainsTo != null) {
      lines.add('Route drains toward ${c.drainsTo} (USGS NLDI).');
    }
    final fc = c.runoffForecast;
    if (fc != null) {
      lines.add('NRCS water-supply forecast: ${fc.name} Apr-Jul runoff '
          '${fc.pctMedian}% of normal (pub ${fc.publication}). Primary dry-year signal.');
    }
    final sn = c.snowpack;
    if (sn != null && sn.pctMedian != null) {
      lines.add('NRCS snowpack: April-1 SWE ${sn.pctMedian}% of median.');
    }
    final g = c.gage;
    if (g != null) {
      lines.add('Connected gage: ${g.name} #${g.id} at ${g.cfs} cfs '
          '(≈${g.pctOfMedian ?? '?'}% of day median).');
    }
    lines.add('US Drought Monitor at start: ${c.drought ?? 'unknown'}.');
    final w = c.weather;
    if (w != null) {
      lines.add('NWS forecast: ${w.summary}, ${w.tempF}°F, precip ${w.precipPct}%.');
    }
    lines.add('Dry-year flag: ${c.dryYear}'
        '${c.dryYearBasis != null ? ' (basis: ${c.dryYearBasis})' : ''}.');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current conditions (provenance)',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...lines.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(
                          child:
                              Text(l, style: theme.textTheme.bodySmall)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
