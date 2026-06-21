import 'dart:math' as math;

/// A WGS84 coordinate. Stored lon-first to match the Python tuples `(lon, lat)`.
class LL {
  final double lon;
  final double lat;
  const LL(this.lon, this.lat);
}

/// Great-circle distance between two points, in meters.
double haversine(LL a, LL b) {
  const r = 6371000.0;
  final p1 = _rad(a.lat), p2 = _rad(b.lat);
  final dphi = _rad(b.lat - a.lat), dl = _rad(b.lon - a.lon);
  final x = math.pow(math.sin(dphi / 2), 2) +
      math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
  return 2 * r * math.asin(math.sqrt(x));
}

double _rad(double deg) => deg * math.pi / 180.0;

/// Cumulative along-track distance in meters, one entry per point.
List<double> cumulative(List<LL> pts) {
  final cum = <double>[0.0];
  for (var i = 1; i < pts.length; i++) {
    cum.add(cum.last + haversine(pts[i - 1], pts[i]));
  }
  return cum;
}

/// (west, south, east, north)
List<double> bbox(List<LL> pts) {
  final xs = pts.map((p) => p.lon);
  final ys = pts.map((p) => p.lat);
  return [
    xs.reduce(math.min),
    ys.reduce(math.min),
    xs.reduce(math.max),
    ys.reduce(math.max),
  ];
}

double round5(double v) => (v * 100000).round() / 100000.0;
double round2(double v) => (v * 100).round() / 100.0;

/// Rounded bbox string for stable URLs (5 decimals ~ 1 m).
String bboxStr(double w, double s, double e, double n, {double pad = 0.0}) =>
    '${round5(w - pad)},${round5(s - pad)},${round5(e + pad)},${round5(n + pad)}';

/// Intersection point of segment p1-p2 with p3-p4 in lon/lat, or null.
LL? segInt(LL p1, LL p2, LL p3, LL p4) {
  final x1 = p1.lon, y1 = p1.lat, x2 = p2.lon, y2 = p2.lat;
  final x3 = p3.lon, y3 = p3.lat, x4 = p4.lon, y4 = p4.lat;
  final den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
  if (den.abs() < 1e-15) return null;
  final t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den;
  final u = ((x1 - x3) * (y1 - y2) - (y1 - y3) * (x1 - x2)) / den;
  if (t >= 0 && t <= 1 && u >= 0 && u <= 1) {
    return LL(x1 + t * (x2 - x1), y1 + t * (y2 - y1));
  }
  return null;
}

/// Local meters-per-degree at a latitude: (klon, klat).
List<double> scaleAt(double lat0) {
  const klat = 111320.0;
  return [111320.0 * math.cos(_rad(lat0)), klat];
}

/// Approx meters from pt to a polyline, both in lon/lat, using the local scale.
double distM(LL pt, List<LL> line, double klon, double klat) {
  final px = pt.lon * klon, py = pt.lat * klat;
  var best = 1e18;
  for (var i = 0; i < line.length - 1; i++) {
    final ax = line[i].lon * klon, ay = line[i].lat * klat;
    final bx = line[i + 1].lon * klon, by = line[i + 1].lat * klat;
    final dx = bx - ax, dy = by - ay;
    final seg2 = dx * dx + dy * dy;
    final t = seg2 == 0
        ? 0.0
        : math.max(0.0, math.min(1.0, ((px - ax) * dx + (py - ay) * dy) / seg2));
    final cx = ax + t * dx, cy = ay + t * dy;
    final d = math.sqrt(math.pow(px - cx, 2) + math.pow(py - cy, 2));
    if (d < best) best = d;
  }
  return best;
}
