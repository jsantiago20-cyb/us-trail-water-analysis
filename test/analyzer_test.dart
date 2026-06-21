import 'package:flutter_test/flutter_test.dart';

import 'package:us_trail_water_analysis/analysis/classify.dart';
import 'package:us_trail_water_analysis/analysis/geometry.dart';
import 'package:us_trail_water_analysis/analysis/gpx.dart';
import 'package:us_trail_water_analysis/analysis/models.dart';
import 'package:us_trail_water_analysis/analysis/report.dart';

const _sampleGpx = '''
<?xml version="1.0"?>
<gpx version="1.1"><trk><name>Test Route</name><trkseg>
<trkpt lat="39.4000" lon="-105.2700"></trkpt>
<trkpt lat="39.4010" lon="-105.2700"></trkpt>
<trkpt lat="39.4020" lon="-105.2700"></trkpt>
</trkseg></trk></gpx>
''';

void main() {
  group('GPX parsing', () {
    test('extracts points lon-first and the route name', () {
      final g = parseGpx(_sampleGpx);
      expect(g.name, 'Test Route');
      expect(g.pts.length, 3);
      expect(g.pts.first.lon, closeTo(-105.27, 1e-9));
      expect(g.pts.first.lat, closeTo(39.40, 1e-9));
    });

    test('tolerates lon-before-lat attribute order', () {
      final g = parseGpx('<gpx><trkpt lon="-105.0" lat="39.0"></trkpt>'
          '<trkpt lon="-105.0" lat="39.1"></trkpt></gpx>');
      expect(g.pts.length, 2);
      expect(g.pts.first.lon, -105.0);
      expect(g.pts.first.lat, 39.0);
    });

    test('round-trips through buildGpx', () {
      final g = parseGpx(_sampleGpx);
      final rebuilt = buildGpx(g.pts.reversed.toList(), '${g.name} (Reversed)');
      final back = parseGpx(rebuilt);
      expect(back.name, 'Test Route (Reversed)');
      expect(back.pts.length, 3);
      expect(back.pts.first.lat, closeTo(39.4020, 1e-6));
    });
  });

  group('geometry', () {
    test('haversine ~111 m for 0.001 deg of latitude', () {
      final d = haversine(const LL(-105.0, 39.0), const LL(-105.0, 39.001));
      expect(d, closeTo(111.0, 2.0));
    });

    test('cumulative is monotonic and starts at zero', () {
      final g = parseGpx(_sampleGpx);
      final cum = cumulative(g.pts);
      expect(cum.first, 0.0);
      expect(cum[1], greaterThan(0));
      expect(cum.last, greaterThan(cum[1]));
    });
  });

  group('classification (dry-year semantics from the reference)', () {
    Conditions dry() => Conditions(
          dryYear: true,
          dryYearBasis: 'water-supply forecast',
          recentRain: false,
          asOf: '2026-06-06',
          runoffForecast: RunoffForecast(
            point: 'x',
            name: 'South Platte',
            pctMedian: 44,
            valueKacft: 61,
            normalKacft: 140,
            period: 'Apr-Jul',
            publication: '2026-04-16',
          ),
        );

    Feature feat(String perm) => Feature(
        mileLo: 7.5, mileHi: 7.8, perm: perm, hits: 3, name: null, lat: 39.4, lon: -105.27, ridx: 0);

    test('perennial collector reads flowing but reduced in a dry year', () {
      final f = feat('perennial');
      classify(f, dry());
      expect(f.label.toLowerCase(), contains('flowing'));
      expect(f.confidence, 'high');
    });

    test('intermittent draw reads likely dry in a dry year', () {
      final f = feat('intermittent');
      classify(f, dry());
      expect(f.label.toLowerCase(), contains('dry'));
    });

    test('ephemeral draw reads dry unless recent rain', () {
      final f = feat('ephemeral');
      classify(f, dry());
      expect(f.label, 'Likely dry unless recent rain');
    });

    test('perennial reads reliable in a normal year', () {
      final f = feat('perennial');
      final cond = Conditions(dryYear: false, recentRain: false, asOf: '2026-06-06');
      classify(f, cond);
      expect(f.label, 'Likely flowing — reliable');
    });
  });

  group('report rendering', () {
    test('produces the expected markdown structure', () {
      final f = Feature(
          mileLo: 7.49, mileHi: 7.84, perm: 'perennial', hits: 4, name: null,
          lat: 39.4, lon: -105.27, ridx: 0)
        ..trail = 'Songbird Trail'
        ..elevFt = 7134;
      classify(
          f,
          Conditions(
              dryYear: true,
              dryYearBasis: 'water-supply forecast',
              recentRain: false,
              asOf: '2026-06-06'));
      final r = AnalysisResult(
        routeName: 'Reynolds North Fork (Reversed)',
        direction: 'reversed',
        totalDistanceMi: 12.02,
        bbox: const [-105.3, 39.3, -105.2, 39.5],
        analysisDate: '2026-06-06',
        headline: Headline(f),
        features: [f],
        conditions: Conditions(
            dryYear: true,
            dryYearBasis: 'water-supply forecast',
            recentRain: false,
            asOf: '2026-06-06'),
        reversedGpx: null,
      );
      final md = renderMarkdown(r);
      expect(md, contains('# Water sources along Reynolds North Fork (Reversed)'));
      expect(md, contains('**Most reliable water:** Songbird Trail'));
      expect(md, contains('| trail | mile | likely flow | type | elev(ft) | conf | stream |'));
      expect(md, contains('Songbird Trail'));
    });
  });
}
