import 'dart:convert';
import 'dart:math' as math;
import 'geometry.dart';
import 'models.dart';
import 'net.dart';

const fcode = <int, String>{
  46006: 'perennial',
  46003: 'intermittent',
  46007: 'ephemeral',
  55800: 'artificial',
  33600: 'canal',
  46000: 'stream',
};

const permRank = <String, int>{
  'perennial': 3,
  'intermittent': 2,
  'ephemeral': 1,
  'artificial': 0,
  'canal': 0,
  'stream': 1,
};

const _nhdUrl =
    'https://hydro.nationalmap.gov/arcgis/rest/services/nhd/MapServer/6/query';

/// Fill elevations along the route. Returns a sparse {routeIndex: feet}.
///
/// Primary source is Open-Meteo's elevation API: it is CORS-enabled (works in
/// the browser), batches up to 100 points per request, and returns in one round
/// trip — so a whole route is one or two fast calls instead of dozens. Falls
/// back to open-elevation (native only) and then to USGS 3DEP EPQS (parallel).
Future<Map<int, int>> elevations(Net net, List<LL> pts,
    {int step = 12, bool web = false, int maxSamples = 100}) async {
  // Cap the number of sampled points so the batch stays within the API limit
  // and a very long route never explodes into many requests.
  var s = step;
  if (pts.length / s > maxSamples) s = (pts.length / maxSamples).ceil();
  final idx = <int>[];
  for (var i = 0; i < pts.length; i += s) {
    idx.add(i);
  }
  if (idx.isEmpty || idx.last != pts.length - 1) idx.add(pts.length - 1);

  // Primary: Open-Meteo batch elevation (CORS-ok, <=100 pts/call, meters).
  try {
    final out = <int, int>{};
    const chunk = 100;
    final calls = <Future<void>>[];
    for (var c = 0; c < idx.length; c += chunk) {
      final part = idx.sublist(c, math.min(c + chunk, idx.length));
      final lats = part.map((i) => pts[i].lat).join(',');
      final lons = part.map((i) => pts[i].lon).join(',');
      calls.add(() async {
        final j = await net.getJson(
          'om_elev',
          'https://api.open-meteo.com/v1/elevation?latitude=$lats&longitude=$lons',
          timeout: const Duration(seconds: 20),
        );
        final el = j['elevation'] as List;
        for (var k = 0; k < part.length && k < el.length; k++) {
          out[part[k]] = ((el[k] as num).toDouble() * 3.281).round();
        }
      }());
    }
    await Future.wait(calls);
    if (out.isNotEmpty) return out;
  } catch (_) {/* fall through */}

  // Fallback A (native only — no CORS on web): open-elevation batch.
  if (!web) {
    try {
      final body = jsonEncode({
        'locations': [
          for (final i in idx) {'latitude': pts[i].lat, 'longitude': pts[i].lon}
        ]
      });
      final res = await net.getJson(
        'elev',
        'https://api.open-elevation.com/api/v1/lookup',
        body: body,
        headers: {'Content-Type': 'application/json'},
      );
      final results = res['results'] as List;
      final out = <int, int>{};
      for (var k = 0; k < idx.length && k < results.length; k++) {
        final e = (results[k]['elevation'] as num).toDouble();
        out[idx[k]] = (e * 3.281).round();
      }
      if (out.isNotEmpty) return out;
    } catch (_) {/* fall through */}
  }

  // Fallback B: USGS 3DEP EPQS, per point but issued in parallel.
  final ele = <int, int>{};
  await Future.wait(idx.map((i) async {
    final x = pts[i].lon, y = pts[i].lat;
    try {
      final j = await net.getJson(
        'epqs',
        'https://epqs.nationalmap.gov/v1/json?x=$x&y=$y&units=Feet&wkid=4326',
        timeout: const Duration(seconds: 15),
      );
      final value = j['value'];
      if (value != null) ele[i] = double.parse(value.toString()).round();
    } catch (_) {/* skip this point */}
  }));
  return ele;
}

int? elevNear(Map<int, int> ele, int i) {
  if (ele.isEmpty) return null;
  int? bestKey;
  var bestDist = 1 << 30;
  for (final k in ele.keys) {
    final d = (k - i).abs();
    if (d < bestDist) {
      bestDist = d;
      bestKey = k;
    }
  }
  return ele[bestKey];
}

class _Raw {
  final double mile;
  final int ridx;
  final double lon;
  final double lat;
  final String perm;
  final String? name;
  _Raw(this.mile, this.ridx, this.lon, this.lat, this.perm, this.name);
}

/// Query NHD flowlines in the route bbox and intersect them against the route.
/// Each intersection is a crossing tagged with the stream's permanence.
Future<List<Feature>> nhdCrossings(Net net, List<LL> pts, List<double> cum) async {
  final bb = bbox(pts);
  final params = {
    'f': 'json',
    'geometry': bboxStr(bb[0], bb[1], bb[2], bb[3]),
    'geometryType': 'esriGeometryEnvelope',
    'inSR': '4326',
    'outSR': '4326',
    'spatialRel': 'esriSpatialRelIntersects',
    'where': '1=1',
    'outFields': 'gnis_name,fcode,ftype',
    'returnGeometry': 'true',
    // Generalize the returned geometry: ~5.5 m tolerance and 6-decimal
    // coordinates. This is plenty precise to detect a route crossing a stream
    // but shrinks the payload ~7x (≈160 KB -> ≈24 KB) and the on-device
    // intersection math accordingly — critical on a phone connection.
    'maxAllowableOffset': '0.00005',
    'geometryPrecision': '6',
  };
  final url = '$_nhdUrl?${Uri(queryParameters: params).query}';
  final j = await net.getJson('nhd', url, timeout: const Duration(seconds: 45));
  final feats = (j['features'] as List?) ?? [];

  final raw = <_Raw>[];
  for (final f in feats) {
    final a = f['attributes'] as Map;
    final fc = a['fcode'];
    final perm = fcode[fc is int ? fc : int.tryParse('$fc')] ?? '$fc';
    final name = a['gnis_name'] as String?;
    final paths = (f['geometry']?['paths'] as List?) ?? [];
    for (final path in paths) {
      final pl = path as List;
      for (var k = 0; k < pl.length - 1; k++) {
        final s3 = LL((pl[k][0] as num).toDouble(), (pl[k][1] as num).toDouble());
        final s4 = LL((pl[k + 1][0] as num).toDouble(), (pl[k + 1][1] as num).toDouble());
        for (var i = 0; i < pts.length - 1; i++) {
          final ip = segInt(pts[i], pts[i + 1], s3, s4);
          if (ip != null) {
            // mile at nearest route vertex
            var j2 = 0;
            var best = double.infinity;
            for (var q = 0; q < pts.length; q++) {
              final d = (pts[q].lon - ip.lon) * (pts[q].lon - ip.lon) +
                  (pts[q].lat - ip.lat) * (pts[q].lat - ip.lat);
              if (d < best) {
                best = d;
                j2 = q;
              }
            }
            raw.add(_Raw(round2(cum[j2] / 1609.34), j2, round5(ip.lon),
                round5(ip.lat), perm, (name != null && name.isNotEmpty) ? name : null));
          }
        }
      }
    }
  }
  raw.sort((a, b) => a.mile.compareTo(b.mile));
  return _cluster(raw);
}

/// Merge adjacent same-permanence crossings into features.
List<Feature> _cluster(List<_Raw> raw, {double gapMi = 0.25}) {
  final groups = <List<_Raw>>[];
  var cur = <_Raw>[];
  for (final c in raw) {
    if (cur.isNotEmpty &&
        (c.mile - cur.last.mile > gapMi || c.perm != cur.last.perm)) {
      groups.add(cur);
      cur = [];
    }
    cur.add(c);
  }
  if (cur.isNotEmpty) groups.add(cur);

  final feats = <Feature>[];
  for (final cl in groups) {
    final names = cl.where((c) => c.name != null).map((c) => c.name!).toList();
    feats.add(Feature(
      mileLo: cl.map((c) => c.mile).reduce((a, b) => a < b ? a : b),
      mileHi: cl.map((c) => c.mile).reduce((a, b) => a > b ? a : b),
      perm: cl.first.perm,
      hits: cl.length,
      name: names.isNotEmpty ? names.first : null,
      lat: cl.first.lat,
      lon: cl.first.lon,
      ridx: cl.first.ridx,
    ));
  }
  return feats;
}
