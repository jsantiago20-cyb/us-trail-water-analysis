import 'models.dart';

class _Class {
  final String label;
  final String confidence;
  final String rationale;
  _Class(this.label, this.confidence, this.rationale);
}

/// Base label from NHD permanence, adjusted by the current-conditions layer.
/// Mirrors the reference classifier exactly.
void classify(Feature feat, Conditions cond) {
  final perm = feat.perm;
  final dryYear = cond.dryYear;
  final fc = cond.runoffForecast;
  final snow = cond.snowpack;

  String dryTxt;
  if (fc?.pctMedian != null) {
    dryTxt = 'Apr-Jul runoff forecast ${fc!.pctMedian}% of normal';
  } else if (snow?.pctMedian != null) {
    dryTxt = 'April-1 snowpack ${snow!.pctMedian}% of median';
  } else {
    dryTxt = 'snowpack and runoff below normal';
  }

  final base = <String, List<String>>{
    'perennial': ['Likely flowing', 'high'],
    'intermittent': ['Seasonal', 'medium'],
    'ephemeral': ['Dry unless recent rain', 'medium'],
    'artificial': ['Artificial channel', 'low'],
    'canal': ['Artificial channel', 'low'],
    'stream': ['Unverified', 'low'],
  }[perm] ?? ['Unverified', 'low'];

  var label = base[0];
  final conf = base[1];
  final rationale = <String>['NHD $perm'];

  if (perm == 'perennial') {
    if (dryYear) {
      label = 'Likely flowing (collector); reduced in dry year';
      rationale.add('valley collector holds flow; $dryTxt');
    } else {
      label = 'Likely flowing — reliable';
    }
  } else if (perm == 'intermittent') {
    if (dryYear) {
      label = 'Likely dry or a trickle';
      rationale.add('intermittent draw; $dryTxt, runoff in recession');
    } else {
      label = 'Seasonal — flowing in runoff, dry later';
    }
  } else if (perm == 'ephemeral') {
    label = 'Likely dry unless recent rain';
    if (cond.recentRain) {
      label = 'Possibly flowing after recent rain';
      rationale.add('recent/forecast convection');
    }
  }

  final c = _Class(label, conf, rationale.join('; '));
  feat.label = c.label;
  feat.confidence = c.confidence;
  feat.rationale = c.rationale;
}
