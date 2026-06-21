import 'classify.dart';
import 'conditions.dart';
import 'geometry.dart';
import 'gpx.dart';
import 'hydrology.dart';
import 'models.dart';
import 'net.dart';
import 'osm.dart';

/// End-to-end analysis, ported from the Python `analyze()`.
///
/// parse GPX -> geometry -> optional reverse -> elevation -> NHD crossings ->
/// cluster -> OSM names -> conditions -> classify -> result.
Future<AnalysisResult> analyze(
  String gpxText, {
  bool reverse = false,
  DateTime? when,
  // Reports a human-readable status plus a 0..1 completion fraction so the UI
  // can show a real progress bar.
  void Function(String message, double progress)? onProgress,
  // On web some upstreams omit CORS headers; when true the analyzer routes
  // around them (USGS EPQS for elevation, a CORS-enabled Overpass mirror).
  bool web = false,
}) async {
  final net = Net();
  // The nine data sources that fill the progress bar as each one returns.
  const totalSteps = 9;
  var doneSteps = 0;
  void prog(String msg) => onProgress?.call(msg, doneSteps / totalSteps);
  try {
    when ??= DateTime.now();
    final whenDate = DateTime(when.year, when.month, when.day);

    prog('Reading route…');
    final gpx = parseGpx(gpxText);
    var pts = gpx.pts;
    if (pts.length < 2) {
      throw Exception('No track points found in this GPX file.');
    }

    String? reversedGpx;
    if (reverse) {
      pts = pts.reversed.toList();
      reversedGpx = buildGpx(pts, '${gpx.name} (Reversed)');
    }

    final cum = cumulative(pts);
    final totalMi = cum.last / 1609.34;

    // Records any source that didn't complete (kept internal; the UI no longer
    // surfaces a retry — with no timeouts everything is expected to finish).
    final incomplete = <String>{};
    Future<T> guard<T>(String label, Future<T> f, T fallback) async {
      try {
        final r = await f;
        doneSteps++;
        prog('Loaded $label');
        return r;
      } catch (_) {
        incomplete.add(label);
        doneSteps++;
        prog('Skipped $label (unavailable)');
        return fallback;
      }
    }

    // Stream crossings are the heart of the report, so fetch them FIRST and on
    // their own — full bandwidth, no competing with the (large) NRCS station
    // downloads — with aggressive auto-retry inside nhdCrossings. This is what
    // guarantees crossings complete on the first run.
    prog('Finding stream crossings (USGS NHD)…');
    final feats = await guard('stream crossings', nhdCrossings(net, pts, cum), <Feature>[]);

    // Then everything else (geometry-only) concurrently.
    prog('Fetching elevation, trail names and conditions…');
    final w1 = await Future.wait<Object?>([
      guard('elevation', elevations(net, pts, web: web), <int, int>{}),
      guard('trail names', overpassFeatures(net, pts, web: web), OsmFeatures([], [])),
      guard('weather', forecast(net, pts), null),
      guard('receiving stream', nldiDownstream(net, pts), (null, <Map<String, String?>>[])),
      guard('snowpack', nrcsSnowpack(net, pts, whenDate), null),
      guard('drought', drought(net, pts), null),
    ]);
    final ele = w1[0] as Map<int, int>;
    final osm = w1[1] as OsmFeatures;
    final wx = w1[2] as Weather?;
    final (drainsTo, nldiGages) = w1[3] as (String?, List<Map<String, String?>>);
    final snow = w1[4] as Snowpack?;
    final usdm = w1[5] as String?;

    attachNames(feats, osm);
    for (final f in feats) {
      f.elevFt = elevNear(ele, f.ridx);
    }

    // Wave 2: the two calls that depend on wave-1 results, also concurrent.
    final state = wx?.state;
    final w2 = await Future.wait<Object?>([
      guard('water-supply forecast', nrcsForecast(net, pts, state, whenDate), null),
      guard(
          'streamflow gage',
          nldiGages.isNotEmpty
              ? gageSnapshot(net, nldiGages, whenDate)
              : Future<Gage?>.value(null),
          null),
    ]);
    final fcst = w2[0] as RunoffForecast?;
    final gage = w2[1] as Gage?;

    // Dry-year signal, in priority order:
    //  1. NRCS April-July water-supply forecast below 70% of normal
    //  2. NRCS April-1 snowpack below 70% of median
    //  3. Hydrologically-connected gage below its 25th percentile
    final fcstDry = fcst != null && fcst.pctMedian < 70;
    final snowDry = snow?.pctMedian != null && snow!.pctMedian! < 70;
    final gageDry = gage?.belowP25 == true;
    final basis = fcstDry
        ? 'water-supply forecast'
        : snowDry
            ? 'snowpack'
            : gageDry
                ? 'gage'
                : null;

    final cond = Conditions(
      drainsTo: drainsTo,
      runoffForecast: fcst,
      snowpack: snow,
      gage: gage,
      drought: usdm,
      weather: wx,
      dryYear: fcstDry || snowDry || gageDry,
      dryYearBasis: basis,
      recentRain: wx?.precipPct != null && wx!.precipPct! >= 40,
      asOf: _ymd(whenDate),
    );

    for (final f in feats) {
      classify(f, cond);
    }

    final perennial = feats.where((f) => f.perm == 'perennial').toList();
    Feature? best;
    for (final f in perennial) {
      if (best == null || f.hits > best.hits) best = f;
    }

    onProgress?.call('Done', 1.0);
    return AnalysisResult(
      routeName: gpx.name + (reverse ? ' (Reversed)' : ''),
      direction: reverse ? 'reversed' : 'forward',
      totalDistanceMi: round2(totalMi),
      bbox: bbox(pts).map(round5).toList(),
      analysisDate: _ymd(whenDate),
      headline: Headline(best),
      features: feats,
      conditions: cond,
      reversedGpx: reversedGpx,
      incompleteSources: incomplete.toList(),
    );
  } finally {
    net.close();
  }
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
