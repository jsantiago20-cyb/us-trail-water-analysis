import 'geometry.dart';

class Gpx {
  final List<LL> pts; // (lon, lat)
  final String name;
  Gpx(this.pts, this.name);
}

/// Parse a GPX document into a route polyline.
///
/// Tolerant of attribute order and self-closing tags: it pulls `lat`/`lon` out
/// of every `<trkpt>`, falling back to `<rtept>` when there is no track. Points
/// are stored lon-first to match the reference analyzer.
Gpx parseGpx(String txt) {
  List<LL> extract(String tag) {
    final out = <LL>[];
    final tagRe = RegExp('<$tag\\b[^>]*>', caseSensitive: false);
    final latRe = RegExp(r'lat\s*=\s*"([-0-9.]+)"', caseSensitive: false);
    final lonRe = RegExp(r'lon\s*=\s*"([-0-9.]+)"', caseSensitive: false);
    for (final m in tagRe.allMatches(txt)) {
      final frag = m.group(0)!;
      final lat = latRe.firstMatch(frag);
      final lon = lonRe.firstMatch(frag);
      if (lat != null && lon != null) {
        out.add(LL(double.parse(lon.group(1)!), double.parse(lat.group(1)!)));
      }
    }
    return out;
  }

  var pts = extract('trkpt');
  if (pts.isEmpty) pts = extract('rtept');

  final nameMatch = RegExp(r'<name>([^<]+)</name>').firstMatch(txt);
  final name = nameMatch != null ? nameMatch.group(1)!.trim() : 'route';
  return Gpx(pts, name);
}

/// Build a fresh, valid GPX document from a list of points (already in the
/// desired travel order). Used to emit the reversed track for export.
String buildGpx(List<LL> pts, String name) {
  final b = StringBuffer();
  b.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  b.writeln('<gpx version="1.1" creator="US Trail Water Analysis" '
      'xmlns="http://www.topografix.com/GPX/1/1">');
  b.writeln('  <trk>');
  b.writeln('    <name>${_xml(name)}</name>');
  b.writeln('    <trkseg>');
  for (final p in pts) {
    b.writeln('      <trkpt lat="${p.lat}" lon="${p.lon}"></trkpt>');
  }
  b.writeln('    </trkseg>');
  b.writeln('  </trk>');
  b.writeln('</gpx>');
  return b.toString();
}

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
