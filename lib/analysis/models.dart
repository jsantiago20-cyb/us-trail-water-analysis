/// A clustered water source along the route.
class Feature {
  double mileLo;
  double mileHi;
  String perm; // perennial | intermittent | ephemeral | artificial | canal | stream
  int hits;
  String? name; // stream name, where known
  double lat;
  double lon;
  int ridx; // index into the route polyline
  String? trail; // nearest OSM trail name
  int? elevFt;

  // classification (filled by classify())
  String label = '';
  String confidence = '';
  String rationale = '';

  Feature({
    required this.mileLo,
    required this.mileHi,
    required this.perm,
    required this.hits,
    required this.name,
    required this.lat,
    required this.lon,
    required this.ridx,
  });

  String get mileRange => mileLo == mileHi
      ? mileLo.toStringAsFixed(2)
      : '${mileLo.toStringAsFixed(2)}-${mileHi.toStringAsFixed(2)}';

  Map<String, dynamic> toJson() => {
        'mile_lo': mileLo,
        'mile_hi': mileHi,
        'perm': perm,
        'hits': hits,
        'name': name,
        'lat': lat,
        'lon': lon,
        'ridx': ridx,
        'trail': trail,
        'elev_ft': elevFt,
        'label': label,
        'confidence': confidence,
        'rationale': rationale,
      };
}

class RunoffForecast {
  final String point;
  final String? name;
  final int pctMedian;
  final double valueKacft;
  final double normalKacft;
  final String period;
  final String publication;

  RunoffForecast({
    required this.point,
    required this.name,
    required this.pctMedian,
    required this.valueKacft,
    required this.normalKacft,
    required this.period,
    required this.publication,
  });

  Map<String, dynamic> toJson() => {
        'point': point,
        'name': name,
        'pct_median': pctMedian,
        'value_kacft': valueKacft,
        'normal_kacft': normalKacft,
        'period': period,
        'publication': publication,
      };
}

class SnowStation {
  final String station;
  final String? name;
  final double sweIn;
  final double medianIn;
  final int pctMedian;
  SnowStation(this.station, this.name, this.sweIn, this.medianIn, this.pctMedian);
  Map<String, dynamic> toJson() => {
        'station': station,
        'name': name,
        'swe_in': sweIn,
        'median_in': medianIn,
        'pct_median': pctMedian,
      };
}

class Snowpack {
  final List<SnowStation> stations;
  final int? pctMedian;
  final String april1;
  final String? nearest;
  Snowpack({required this.stations, required this.pctMedian, required this.april1, required this.nearest});
  Map<String, dynamic> toJson() => {
        'stations': stations.map((s) => s.toJson()).toList(),
        'pct_median': pctMedian,
        'april1': april1,
        'nearest': nearest,
      };
}

class Gage {
  final String id;
  final String? name;
  final double cfs;
  final String asOf;
  final Map<String, double?>? stats;
  int? pctOfMedian;
  bool? belowP25;
  Gage({required this.id, required this.name, required this.cfs, required this.asOf, required this.stats});
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cfs': cfs,
        'as_of': asOf,
        'stats': stats,
        'pct_of_median': pctOfMedian,
        'below_p25': belowP25,
      };
}

class Weather {
  final String summary;
  final int? tempF;
  final int? precipPct;
  final String? state;
  Weather({
    required this.summary,
    required this.tempF,
    required this.precipPct,
    required this.state,
  });
  Map<String, dynamic> toJson() => {
        'summary': summary,
        'temp_f': tempF,
        'precip_pct': precipPct,
        'state': state,
      };
}

class Conditions {
  String? drainsTo;
  RunoffForecast? runoffForecast;
  Snowpack? snowpack;
  Gage? gage;
  String? drought;
  String? fireAlert; // active Red Flag Warning / Fire Weather Watch, else null
  Weather? weather;
  bool dryYear;
  String? dryYearBasis;
  bool recentRain;
  String asOf;

  Conditions({
    this.drainsTo,
    this.runoffForecast,
    this.snowpack,
    this.gage,
    this.drought,
    this.fireAlert,
    this.weather,
    required this.dryYear,
    this.dryYearBasis,
    required this.recentRain,
    required this.asOf,
  });

  Map<String, dynamic> toJson() => {
        'drains_to': drainsTo,
        'runoff_forecast': runoffForecast?.toJson(),
        'snowpack': snowpack?.toJson(),
        'gage': gage?.toJson(),
        'drought': drought,
        'fire_alert': fireAlert,
        'weather': weather?.toJson(),
        'dry_year': dryYear,
        'dry_year_basis': dryYearBasis,
        'recent_rain': recentRain,
        'as_of': asOf,
      };
}

class Headline {
  final Feature? mostReliable;
  Headline(this.mostReliable);
}

class AnalysisResult {
  final String routeName;
  final String direction;
  final double totalDistanceMi;
  final List<double> bbox;
  final String analysisDate;
  final Headline headline;
  final List<Feature> features;
  final Conditions conditions;
  final String? reversedGpx;

  /// Human-readable names of data sources that did not complete (timed out or
  /// errored) during this run. Empty when every source returned. Lets the UI
  /// distinguish "no water found" from "couldn't finish loading" and offer a
  /// retry instead of presenting incomplete data as final.
  final List<String> incompleteSources;

  AnalysisResult({
    required this.routeName,
    required this.direction,
    required this.totalDistanceMi,
    required this.bbox,
    required this.analysisDate,
    required this.headline,
    required this.features,
    required this.conditions,
    required this.reversedGpx,
    this.incompleteSources = const [],
  });

  bool get isComplete => incompleteSources.isEmpty;

  Map<String, dynamic> toJson() => {
        'route': {
          'name': routeName,
          'direction': direction,
          'total_distance_mi': totalDistanceMi,
          'bbox': bbox,
          'analysis_date': analysisDate,
        },
        'headline': {
          'most_reliable': headline.mostReliable == null
              ? null
              : {
                  'mile_lo': headline.mostReliable!.mileLo,
                  'mile_hi': headline.mostReliable!.mileHi,
                  'perm': headline.mostReliable!.perm,
                  'label': headline.mostReliable!.label,
                  'name': headline.mostReliable!.name,
                  'trail': headline.mostReliable!.trail,
                },
        },
        'features': features.map((f) => f.toJson()).toList(),
        'conditions': conditions.toJson(),
      };
}
