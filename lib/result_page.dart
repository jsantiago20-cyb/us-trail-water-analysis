import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'analysis/analyzer.dart';
import 'analysis/models.dart';
import 'analysis/report.dart';

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
  double _fraction = 0; // 0..1 for the progress bar
  String? _error;
  int _runId = 0; // guards against a stale run resolving after a retry

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final myRun = ++_runId;
    setState(() {
      _result = null;
      _error = null;
      _progress = 'Starting…';
      _fraction = 0;
    });
    try {
      final r = await analyze(
        widget.gpxText,
        reverse: widget.reverse,
        when: widget.date,
        web: kIsWeb,
        onProgress: (m, f) {
          if (mounted && myRun == _runId) {
            setState(() {
              _progress = m;
              _fraction = f;
            });
          }
        },
      );
      if (mounted && myRun == _runId) setState(() => _result = r);
    } catch (e) {
      if (mounted && myRun == _runId) setState(() => _error = e.toString());
    }
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
              ? _Loading(progress: _progress, fraction: _fraction)
              : _ResultView(result: _result!),
    );
  }
}

class _Loading extends StatelessWidget {
  final String progress;
  final double fraction;
  const _Loading({required this.progress, required this.fraction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (fraction.clamp(0.0, 1.0) * 100).round();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$pct%',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                // 0 fraction shows an indeterminate bar so the user sees motion
                // before the first source returns; a real value after that.
                value: fraction <= 0 ? null : fraction.clamp(0.0, 1.0),
                minHeight: 12,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 16),
            Text(progress,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Querying USGS, NRCS, OpenStreetMap and NWS. No time limit — '
              'every source runs to completion.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
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
  const _ResultView({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = result;
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
        if (r.headline.mostReliable != null) _HeadlineCard(f: r.headline.mostReliable!, dir: r.direction),
        const SizedBox(height: 16),
        Text('Water sources in travel order',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (r.features.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'No mapped stream crossings were found along this route.'),
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
