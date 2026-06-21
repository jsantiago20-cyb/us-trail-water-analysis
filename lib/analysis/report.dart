import 'models.dart';

/// Render the analysis as the same markdown report the Python tool produces,
/// for export/share.
String renderMarkdown(AnalysisResult r) {
  final out = <String>[];
  out.add('# Water sources along ${r.routeName}');
  out.add('Direction: ${r.direction} | Distance: ${r.totalDistanceMi} mi | '
      'Date: ${r.analysisDate}\n');

  final hl = r.headline.mostReliable;
  if (hl != null) {
    final where = hl.trail ?? 'off-trail';
    final nm = hl.name != null ? ', ${hl.name}' : '';
    out.add('**Most reliable water:** $where, ${r.direction} mile '
        '${hl.mileLo.toStringAsFixed(2)}–${hl.mileHi.toStringAsFixed(2)}$nm '
        '(${hl.perm}). ${hl.label}.\n');
  }

  out.add('## Water sources in travel order\n');
  out.add('Listed by trail and mile. Stream name shown where known.\n');
  out.add('| trail | mile | likely flow | type | elev(ft) | conf | stream |');
  out.add('|---|---|---|---|---|---|---|');
  for (final f in r.features) {
    final trail = f.trail ?? 'off-trail';
    final stream = f.name ?? '';
    out.add('| $trail | ${f.mileRange} | ${f.label} | ${f.perm} | '
        '${f.elevFt ?? '?'} | ${f.confidence} | $stream |');
  }

  final c = r.conditions;
  out.add('\n## Current conditions (provenance)\n');
  if (c.drainsTo != null) {
    out.add('- Route drains toward ${c.drainsTo} (USGS NLDI).');
  }
  final fc = c.runoffForecast;
  if (fc != null) {
    out.add('- NRCS water-supply forecast: ${fc.name} Apr-Jul runoff '
        '${fc.pctMedian}% of normal (${fc.valueKacft} of ${fc.normalKacft} kac-ft, '
        'pub ${fc.publication}). Primary dry-year signal.');
  }
  final sn = c.snowpack;
  if (sn != null && sn.pctMedian != null) {
    final names = sn.stations.map((s) => s.name).where((n) => n != null).join(', ');
    out.add('- NRCS snowpack: April-1 SWE ${sn.pctMedian}% of median ($names).');
  }
  final g = c.gage;
  if (g != null) {
    final st = g.stats ?? {};
    out.add('- Connected gage: ${g.name} #${g.id} at ${g.cfs} cfs '
        '(as of ${g.asOf.length >= 16 ? g.asOf.substring(0, 16) : g.asOf}); '
        'day median p50≈${st['p50'] ?? '?'} cfs, ≈${g.pctOfMedian ?? '?'}% of median.');
  }
  out.add('- US Drought Monitor at start: ${c.drought}.');
  final w = c.weather;
  if (w != null) {
    out.add('- NWS forecast: ${w.summary}, ${w.tempF}F, precip ${w.precipPct}%.');
  }
  out.add('- Dry-year flag: ${c.dryYear} (basis: ${c.dryYearBasis}; '
      'downgrades intermittent and ephemeral draws).');
  out.add('\nSmall foothills/backcountry streams are not potable without treatment. '
      'This judges presence of flow, not water quality.');
  return out.join('\n');
}
