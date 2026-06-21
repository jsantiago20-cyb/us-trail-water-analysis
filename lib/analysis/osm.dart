import 'geometry.dart';
import 'models.dart';
import 'net.dart';

/// NHD high-res leaves most small draws unnamed. OSM carries named rivers and,
/// importantly, named trails. Many foothills trails are named for the drainage
/// they follow (e.g. "Oxen Draw Trail"), so the nearest trail names a crossing
/// the way a hiker would refer to it.
const _overpassMirrors = [
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass-api.de/api/interpreter',
  'https://overpass.osm.ch/api/interpreter',
];

// overpass.kumi.systems does not send CORS headers; overpass-api.de does. On web
// we try the CORS-enabled mirror first so the browser doesn't block the request.
const _overpassMirrorsWeb = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
];

class OsmWay {
  final String name;
  final List<LL> geom;
  OsmWay(this.name, this.geom);
}

class OsmFeatures {
  final List<OsmWay> waterways;
  final List<OsmWay> trails;
  OsmFeatures(this.waterways, this.trails);
}

Future<OsmFeatures> overpassFeatures(Net net, List<LL> pts,
    {bool web = false}) async {
  final bb = bbox(pts);
  final s = round5(bb[1]), w = round5(bb[0]), n = round5(bb[3]), e = round5(bb[2]);
  final box = '$s,$w,$n,$e'; // S,W,N,E
  final q = '[out:json][timeout:90];('
      'way["waterway"]["name"]($box);'
      'way["natural"="water"]["name"]($box);'
      'way["highway"~"path|footway|track|bridleway"]["name"]($box);'
      ');out tags geom;';
  final body = 'data=${Uri.encodeQueryComponent(q)}';

  dynamic j;
  for (final mirror in (web ? _overpassMirrorsWeb : _overpassMirrors)) {
    try {
      j = await net.getJson(
        'overpass',
        mirror,
        body: body,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'gpx-water-analysis',
        },
      );
      break;
    } catch (_) {
      continue;
    }
  }
  if (j == null) return OsmFeatures([], []);

  final waterways = <OsmWay>[];
  final trails = <OsmWay>[];
  for (final el in (j['elements'] as List? ?? [])) {
    final t = (el['tags'] as Map?) ?? {};
    final nm = t['name'] as String?;
    final geom = <LL>[
      for (final g in (el['geometry'] as List? ?? []))
        LL((g['lon'] as num).toDouble(), (g['lat'] as num).toDouble())
    ];
    if (nm == null || geom.length < 2) continue;
    if (t['waterway'] != null || t['natural'] == 'water') {
      waterways.add(OsmWay(nm, geom));
    } else if (t['highway'] != null) {
      trails.add(OsmWay(nm, geom));
    }
  }
  return OsmFeatures(waterways, trails);
}

/// Name each feature from the nearest OSM waterway; add trail context.
void attachNames(List<Feature> feats, OsmFeatures osm,
    {double waterBufM = 70, double trailBufM = 45}) {
  if (feats.isEmpty) return;
  final sc = scaleAt(feats.first.lat);
  final klon = sc[0], klat = sc[1];
  for (final f in feats) {
    final pt = LL(f.lon, f.lat);
    if (f.name == null) {
      double? bestD;
      String? bestName;
      for (final ww in osm.waterways) {
        final d = distM(pt, ww.geom, klon, klat);
        if (d <= waterBufM && (bestD == null || d < bestD)) {
          bestD = d;
          bestName = ww.name;
        }
      }
      if (bestName != null) f.name = bestName;
    }
    double? bestTD;
    String? bestTrail;
    for (final tr in osm.trails) {
      final d = distM(pt, tr.geom, klon, klat);
      if (d <= trailBufM && (bestTD == null || d < bestTD)) {
        bestTD = d;
        bestTrail = tr.name;
      }
    }
    f.trail = bestTrail;
  }
}
