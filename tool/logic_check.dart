// ignore_for_file: avoid_print
import 'package:us_trail_water_analysis/analysis/gpx.dart';
import 'package:us_trail_water_analysis/analysis/geometry.dart';
import 'package:us_trail_water_analysis/analysis/classify.dart';
import 'package:us_trail_water_analysis/analysis/models.dart';
import 'package:us_trail_water_analysis/analysis/report.dart';

int fails = 0;
void check(String n, bool c) { print('${c ? "PASS" : "FAIL"} $n'); if(!c) fails++; }

void main() {
  const gpx = '<gpx><trk><name>Test Route</name><trkseg>'
    '<trkpt lat="39.4000" lon="-105.2700"></trkpt>'
    '<trkpt lat="39.4010" lon="-105.2700"></trkpt>'
    '<trkpt lon="-105.2700" lat="39.4020"></trkpt>'
    '</trkseg></trk></gpx>';
  final g = parseGpx(gpx);
  check('parse name', g.name == 'Test Route');
  check('parse 3 pts', g.pts.length == 3);
  check('lon-first', (g.pts[0].lon + 105.27).abs() < 1e-9 && (g.pts[0].lat - 39.40).abs() < 1e-9);
  check('attr order tolerant', (g.pts[2].lat - 39.402).abs() < 1e-9);

  final cum = cumulative(g.pts);
  check('cum starts 0', cum.first == 0.0);
  check('cum monotonic', cum.last > cum[1] && cum[1] > 0);
  final d = haversine(const LL(-105,39), const LL(-105,39.001));
  check('haversine ~111m', (d-111).abs() < 2);

  final rebuilt = buildGpx(g.pts.reversed.toList(), '${g.name} (Reversed)');
  final back = parseGpx(rebuilt);
  check('reverse roundtrip name', back.name == 'Test Route (Reversed)');
  check('reverse first pt', (back.pts.first.lat - 39.4020).abs() < 1e-6);

  Conditions dry() => Conditions(dryYear:true, dryYearBasis:'water-supply forecast',
    recentRain:false, asOf:'2026-06-06',
    runoffForecast: RunoffForecast(point:'x', name:'South Platte', pctMedian:44,
      valueKacft:61, normalKacft:140, period:'Apr-Jul', publication:'2026-04-16'));
  Feature feat(String p) => Feature(mileLo:7.5, mileHi:7.8, perm:p, hits:3, name:null, lat:39.4, lon:-105.27, ridx:0);

  final per = feat('perennial'); classify(per, dry());
  check('perennial flowing/reduced dry-year', per.label.toLowerCase().contains('flowing') && per.confidence=='high');
  final inter = feat('intermittent'); classify(inter, dry());
  check('intermittent likely dry', inter.label.toLowerCase().contains('dry'));
  final eph = feat('ephemeral'); classify(eph, dry());
  check('ephemeral dry unless rain', eph.label == 'Likely dry unless recent rain');
  final perN = feat('perennial'); classify(perN, Conditions(dryYear:false, recentRain:false, asOf:'x'));
  check('perennial reliable normal year', perN.label == 'Likely flowing — reliable');

  final f = Feature(mileLo:7.49, mileHi:7.84, perm:'perennial', hits:4, name:null, lat:39.4, lon:-105.27, ridx:0)
    ..trail='Songbird Trail'..elevFt=7134;
  classify(f, dry());
  final r = AnalysisResult(routeName:'Reynolds North Fork (Reversed)', direction:'reversed',
    totalDistanceMi:12.02, bbox:const[-105.3,39.3,-105.2,39.5], analysisDate:'2026-06-06',
    headline:Headline(f), features:[f], conditions:dry(), reversedGpx:null);
  final md = renderMarkdown(r);
  check('md header', md.contains('# Water sources along Reynolds North Fork (Reversed)'));
  check('md headline', md.contains('**Most reliable water:** Songbird Trail'));
  check('md table header', md.contains('| trail | mile | likely flow | type | elev(ft) | conf | stream |'));

  print('');
  print(fails == 0 ? 'ALL CHECKS PASSED' : '$fails CHECK(S) FAILED');
}
