import 'geometry.dart';
import 'models.dart';
import 'net.dart';

const _nldi = 'https://api.water.usgs.gov/nldi/linked-data';

String? _cleanStream(String? nm) {
  if (nm == null) return null;
  nm = _titleCase(nm);
  for (final suf in [' Nr ', ' Near ', ' Ab ', ' Abv ', ' Above ', ' Bl ', ' Below ', ' At ']) {
    final i = nm!.indexOf(suf);
    if (i > 0) {
      nm = nm.substring(0, i);
      break;
    }
  }
  return nm!.replaceAll(' Ck', ' Creek').replaceAll(' R ', ' River ').trim();
}

String _titleCase(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// Hydrologically connected gages the route drains toward, via USGS NLDI.
/// Returns (receivingStreamName, gages nearest-first).
Future<(String?, List<Map<String, String?>>)> nldiDownstream(
    Net net, List<LL> pts) async {
  final cx = pts.map((p) => p.lon).reduce((a, b) => a + b) / pts.length;
  final cy = pts.map((p) => p.lat).reduce((a, b) => a + b) / pts.length;
  int comid;
  try {
    final pos = await net.getJson('nldi_pos',
        '$_nldi/comid/position?coords=POINT(${round5(cx)}%20${round5(cy)})&f=json');
    comid = (pos['features'][0]['properties']['comid'] as num).toInt();
  } catch (_) {
    return (null, <Map<String, String?>>[]);
  }
  final gages = <Map<String, String?>>[];
  for (final nav in ['DM', 'UT']) {
    try {
      final g = await net.getJson('nldi_${nav}_$comid',
          '$_nldi/comid/$comid/navigation/$nav/nwissite?distance=40&f=json');
      for (final f in (g['features'] as List? ?? [])) {
        final p = f['properties'] as Map;
        final ident = ((p['identifier'] as String?) ?? '').replaceAll('USGS-', '');
        final nm = p['name'] as String?;
        if (ident.isNotEmpty && !gages.any((x) => x['id'] == ident)) {
          gages.add({'id': ident, 'name': nm});
        }
      }
    } catch (_) {
      continue;
    }
  }
  String? drainsTo;
  for (final gg in gages) {
    final c = _cleanStream(gg['name']);
    final up = (gg['name'] ?? '').toUpperCase();
    if (c != null &&
        ['GULCH', 'CREEK', ' CK', 'RIVER'].any((w) => up.contains(w)) &&
        !up.contains('LAKE')) {
      drainsTo = c;
      break;
    }
  }
  return (drainsTo, gages);
}

/// Current 00060 cfs for a single site.
Future<Map<String, dynamic>?> siteFlow(Net net, String gid) async {
  final url =
      'https://waterservices.usgs.gov/nwis/iv/?format=json&sites=$gid&parameterCd=00060';
  try {
    final j = await net.getJson('iv_$gid', url);
    final ts = j['value']['timeSeries'] as List;
    for (final t in ts) {
      final vals = t['values'][0]['value'] as List;
      if (vals.isNotEmpty) {
        final cfs = double.parse(vals.last['value'].toString());
        if (cfs >= 0) {
          return {
            'cfs': cfs,
            'as_of': vals.last['dateTime'],
            'name': t['sourceInfo']['siteName'],
          };
        }
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// Historical daily percentiles for the calendar day from the NWIS stat RDB.
Future<Map<String, double?>?> gageStats(Net net, String gid, DateTime when) async {
  final url = 'https://waterservices.usgs.gov/nwis/stat/?format=rdb'
      '&sites=$gid&statReportType=daily&statTypeCd=p10,p25,p50,p75,p90&parameterCd=00060';
  String raw;
  try {
    raw = await net.getText('gagestat_$gid', url);
  } catch (_) {
    return null;
  }
  for (final line in raw.split('\n')) {
    if (line.startsWith('#') || line.startsWith('agency') || line.startsWith('5s')) {
      continue;
    }
    final p = line.split('\t');
    if (p.length > 13 && p[5] == '${when.month}' && p[6] == '${when.day}') {
      double? g(int i) => i < p.length ? double.tryParse(p[i]) : null;
      return {
        'p10': g(10),
        'p25': g(11),
        'p50': g(12),
        'p75': g(13),
        'p90': p.length > 14 ? g(14) : null,
      };
    }
  }
  return null;
}

/// First connected gage with continuous flow = the current reading for the
/// stream the route drains toward.
Future<Gage?> gageSnapshot(
    Net net, List<Map<String, String?>> gages, DateTime when) async {
  for (final gg in gages) {
    final fl = await siteFlow(net, gg['id']!);
    if (fl == null) continue;
    final st = await gageStats(net, gg['id']!, when);
    final snap = Gage(
      id: gg['id']!,
      name: fl['name'] as String?,
      cfs: fl['cfs'] as double,
      asOf: fl['as_of'] as String,
      stats: st,
    );
    if (st != null && st['p50'] != null) {
      final p50 = st['p50']!;
      snap.pctOfMedian = p50 != 0 ? (100 * snap.cfs / p50).round() : null;
      snap.belowP25 = st['p25'] != null && snap.cfs < st['p25']!;
    }
    return snap;
  }
  return null;
}

/// NRCS April-July streamflow volume forecast (SRVO) as percent of normal.
Future<RunoffForecast?> nrcsForecast(
    Net net, List<LL> pts, String? state, DateTime when) async {
  if (state == null) return null;
  final lat = pts.first.lat, lon = pts.first.lon;
  List stns;
  try {
    stns = await net.getJson('fcst_points_$state',
        'https://wcc.sc.egov.usda.gov/awdbRestApi/services/v1/stations'
        '?stationTriplets=*:$state:USGS&returnStationElements=false') as List;
  } catch (_) {
    return null;
  }
  final withCoords = stns.where((x) => x['latitude'] != null).toList()
    ..sort((a, b) {
      final da = _sq(a['latitude'] - lat) + _sq(a['longitude'] - lon);
      final db = _sq(b['latitude'] - lat) + _sq(b['longitude'] - lon);
      return da.compareTo(db);
    });
  final near = withCoords.take(5);
  for (final st in near) {
    final trip = st['stationTriplet'];
    List data;
    try {
      final j = await net.getJson('fcst_$trip',
          'https://wcc.sc.egov.usda.gov/awdbRestApi/services/v1/forecasts'
          '?stationTriplets=$trip&elementCds=SRVO') as List;
      data = j[0]['data'] as List;
    } catch (_) {
      continue;
    }
    final aj = data.where((d) {
      final fp = d['forecastPeriod'];
      return fp is List &&
          fp.length == 2 &&
          fp[0] == '04-01' &&
          fp[1] == '07-31' &&
          d['periodNormal'] != null;
    }).toList()
      ..sort((a, b) =>
          ('${a['publicationDate'] ?? ''}').compareTo('${b['publicationDate'] ?? ''}'));
    if (aj.isEmpty) continue;
    final d = aj.last;
    final v = d['forecastValues']?['50'];
    if (v == null) continue;
    final value = (v as num).toDouble();
    final normal = (d['periodNormal'] as num).toDouble();
    return RunoffForecast(
      point: trip,
      name: st['name'] as String?,
      pctMedian: (100 * value / normal).round(),
      valueKacft: value,
      normalKacft: normal,
      period: 'Apr-Jul',
      publication: ('${d['publicationDate'] ?? ''}').length >= 10
          ? '${d['publicationDate']}'.substring(0, 10)
          : '${d['publicationDate'] ?? ''}',
    );
  }
  return null;
}

/// April-1 snow-water-equivalent as percent of median at nearby SNOTEL sites.
Future<Snowpack?> nrcsSnowpack(Net net, List<LL> pts, DateTime when) async {
  final lat = pts.first.lat, lon = pts.first.lon;
  List stns;
  try {
    stns = await net.getJson('snotel_stations',
        'https://wcc.sc.egov.usda.gov/awdbRestApi/services/v1/stations?stationTriplets=*:*:SNTL&returnStationElements=false') as List;
  } catch (_) {
    return null;
  }
  final withCoords = stns.where((x) => x['latitude'] != null).toList()
    ..sort((a, b) {
      final da = _sq(a['latitude'] - lat) + _sq(a['longitude'] - lon);
      final db = _sq(b['latitude'] - lat) + _sq(b['longitude'] - lon);
      return da.compareTo(db);
    });
  final near = withCoords.take(3).toList();
  if (near.isEmpty) return null;
  final wy = when.month >= 10 ? when.year + 1 : when.year;
  final april1 = '$wy-04-01';
  final samples = <SnowStation>[];
  for (final st in near) {
    final trip = st['stationTriplet'];
    final u = 'https://wcc.sc.egov.usda.gov/awdbRestApi/services/v1/data'
        '?stationTriplets=$trip&elements=WTEQ&duration=DAILY'
        '&beginDate=$april1&endDate=$april1&returnFlags=false'
        '&centralTendencyType=MEDIAN&returnCentralTendencyData=true';
    try {
      final j = await net.getJson('snotel_${trip}_$wy', u) as List;
      final v = j[0]['data'][0]['values'][0] as Map;
      final val = v['value'];
      final med = v['median'];
      if (val != null && med != null && (med as num) != 0) {
        samples.add(SnowStation(trip, st['name'] as String?,
            (val as num).toDouble(), med.toDouble(),
            (100 * (val).toDouble() / med.toDouble()).round()));
      }
    } catch (_) {
      continue;
    }
  }
  if (samples.isEmpty) {
    return Snowpack(
        stations: [], pctMedian: null, april1: april1, nearest: near.first['name'] as String?);
  }
  final avg =
      (samples.map((s) => s.pctMedian).reduce((a, b) => a + b) / samples.length).round();
  return Snowpack(
      stations: samples, pctMedian: avg, april1: april1, nearest: samples.first.name);
}

/// US Drought Monitor category labels (D0..D4).
const _droughtCats = {
  0: 'D0 (Abnormally Dry)',
  1: 'D1 (Moderate Drought)',
  2: 'D2 (Severe Drought)',
  3: 'D3 (Extreme Drought)',
  4: 'D4 (Exceptional Drought)',
};

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Current US Drought Monitor stage for the COUNTY the route starts in.
///
/// The previous ArcGIS service was dead (returned nothing even for known
/// drought areas). This uses the authoritative path: FCC area API → county FIPS,
/// then the official USDM data service (usdmdataservices.unl.edu) for that
/// county. Returns something like "Jefferson County, CO — D2 (Severe Drought);
/// locally up to D3 (Extreme) in 8% of county", or null if the lookup fails.
Future<String?> drought(Net net, List<LL> pts, DateTime when) async {
  final lat = pts.first.lat, lon = pts.first.lon;

  String? fips, county, stateCode;
  try {
    final j = await net.getJson(
        'fcc', 'https://geo.fcc.gov/api/census/area?lat=$lat&lon=$lon&format=json');
    final res = (j['results'] as List?) ?? [];
    if (res.isNotEmpty) {
      fips = res[0]['county_fips'] as String?;
      county = res[0]['county_name'] as String?;
      stateCode = res[0]['state_code'] as String?;
    }
  } catch (_) {/* fall through */}
  if (fips == null) return null;

  final start = _ymd(when.subtract(const Duration(days: 28)));
  final end = _ymd(when);
  String csv;
  try {
    csv = await net.getText(
        'usdm',
        'https://usdmdataservices.unl.edu/api/CountyStatistics/'
            'GetDroughtSeverityStatisticsByAreaPercent'
            '?aoi=$fips&startdate=$start&enddate=$end&statisticsType=1');
  } catch (_) {
    return null;
  }

  final place = county != null ? '$county, $stateCode' : 'county';
  final lines =
      csv.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.length < 2) return '$place — None (no drought)';

  final header = lines.first.split(',').map((h) => h.trim()).toList();
  final col = {for (var i = 0; i < header.length; i++) header[i]: i};
  final rows = lines.skip(1).map((l) => l.split(',')).toList()
    ..sort((a, b) => b[col['MapDate']!].compareTo(a[col['MapDate']!])); // newest
  final r = rows.first;
  double pc(String name) {
    final i = col[name];
    if (i == null || i >= r.length) return 0;
    return double.tryParse(r[i].trim()) ?? 0;
  }

  // Percentages are cumulative (D0 includes all worse). The county's stage is
  // the most severe category covering a majority; also note the worst present.
  final pct = {for (var i = 0; i <= 4; i++) i: pc('D$i')};
  int? predominant;
  for (var i = 4; i >= 0; i--) {
    if (pct[i]! >= 50) {
      predominant = i;
      break;
    }
  }
  int? worst;
  for (var i = 4; i >= 0; i--) {
    if (pct[i]! > 0) {
      worst = i;
      break;
    }
  }
  if (predominant == null && worst == null) return '$place — None (no drought)';
  final main = predominant ?? worst!;
  var label = '$place — ${_droughtCats[main]}';
  if (worst != null && worst > main && pct[worst]! >= 1) {
    label +=
        '; locally up to ${_droughtCats[worst]} in ${pct[worst]!.round()}% of county';
  }
  return label;
}

/// Active NWS fire-weather alert at the start point (Red Flag Warning or Fire
/// Weather Watch), or null if there is none. This is the authoritative
/// high-fire-danger signal.
Future<String?> fireAlert(Net net, List<LL> pts) async {
  final lat = pts.first.lat, lon = pts.first.lon;
  try {
    final j = await net.getJson(
        'alerts', 'https://api.weather.gov/alerts/active?point=$lat,$lon');
    final feats = (j['features'] as List?) ?? [];
    for (final f in feats) {
      final ev = (f['properties']?['event'] ?? '').toString();
      final l = ev.toLowerCase();
      if (l.contains('red flag') || l.contains('fire weather')) return ev;
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<Weather?> forecast(Net net, List<LL> pts) async {
  final lat = pts.first.lat, lon = pts.first.lon;
  try {
    final p =
        await net.getJson('nwspoint', 'https://api.weather.gov/points/$lat,$lon');
    final props = p['properties'];
    final state = props['relativeLocation']['properties']['state'] as String?;
    final fc = await net.getJson('nwsfc', props['forecast']);
    final per = fc['properties']['periods'][0];
    return Weather(
      summary: per['shortForecast'] as String,
      tempF: (per['temperature'] as num?)?.toInt(),
      precipPct: (per['probabilityOfPrecipitation']?['value'] as num?)?.toInt(),
      state: state,
    );
  } catch (_) {
    return null;
  }
}

double _sq(dynamic v) => ((v as num) * v).toDouble();
