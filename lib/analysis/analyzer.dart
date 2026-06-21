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
  void Function(String message)? onProgress,
  // On web some upstreams omit CORS headers; when true the analyzer routes
  // around them (USGS EPQS for elevation, a CORS-enabled Overpass mirror).
  bool web = false,
}) async {
  final net = Net(onProgress: onProgress);
  void log(String m) => onProgress?.call(m);
  try {
    when ??= DateTime.now();
    final whenDate = DateTime(when.year, when.month, when.day);

    log('Parsing GPX…');
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

    // Wave 1: every call that only needs the route geometry runs concurrently
    // instead of one after another. Each is guarded so a single slow/failed
    // source degrades gracefully rather than failing or blocking the rest.
    log('Fetching map data, elevation and conditions…');
    final w1 = await Future.wait<Object?>([
      _safe(elevations(net, pts, web: web), <int, int>{}),
      _safe(nhdCrossings(net, pts, cum), <Feature>[]),
      _safe(overpassFeatures(net, pts, web: web), OsmFeatures([], [])),
      _safe(forecast(net, pts), null),
      _safe(nldiDownstream(net, pts), (null, <Map<String, String?>>[])),
      _safe(nrcsSnowpack(net, pts, whenDate), null),
      _safe(drought(net, pts), null),
    ]);
    final ele = w1[0] as Map<int, int>;
    final feats = w1[1] as List<Feature>;
    final osm = w1[2] as OsmFeatures;
    final wx = w1[3] as Weather?;
    final (drainsTo, nldiGages) = w1[4] as (String?, List<Map<String, String?>>);
    final snow = w1[5] as Snowpack?;
    final usdm = w1[6] as String?;

    attachNames(feats, osm);
    for (final f in feats) {
      f.elevFt = elevNear(ele, f.ridx);
    }

    // Wave 2: the two calls that depend on wave-1 results, also concurrent.
    final state = wx?.state;
    final w2 = await Future.wait<Object?>([
      _safe(nrcsForecast(net, pts, state, whenDate), null),
      _safe(
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

    log('Done.');
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
    );
  } finally {
    net.close();
  }
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Await [f], but never throw: on any error return [fallback]. Lets the parallel
/// waves treat a slow or unavailable data source as "missing" instead of fatal.
Future<T> _safe<T>(Future<T> f, T fallback) async {
  try {
    return await f;
  } catch (_) {
    return fallback;
  }
}
