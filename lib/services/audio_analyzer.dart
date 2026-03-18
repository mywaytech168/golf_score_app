import 'dart:io';
import 'dart:math';

/// Lightweight audio analyzer implemented in Dart for in-app use.
/// Works on PCM float samples (range ~ -1..1) and basic FFT implemented here.

const double _eps = 1e-12;

class AudioFeatures {
  final double rmsDbfs;
  final double spectralCentroid;
  final double sharpnessHfxLoud;
  final double highbandAmp;
  final double peakDbfs;
  final Map<String, double> bandPeaks; // band_{lo}k_{hi}k_peak_amp

  AudioFeatures({
    required this.rmsDbfs,
    required this.spectralCentroid,
    required this.sharpnessHfxLoud,
    required this.highbandAmp,
    required this.peakDbfs,
    required this.bandPeaks,
  });

  Map<String, double> toMap() {
    final m = <String, double>{
      'rms_dbfs': rmsDbfs, // Corrected typo from rmsDbFs
      'spectral_centroid': spectralCentroid,
      'sharpness_hfxloud': sharpnessHfxLoud,
      'highband_amp': highbandAmp,
      'peak_dbfs': peakDbfs, // Corrected typo from peakDbFs
    };
    m.addAll(bandPeaks);
    return m;
  }
}

// Simple recursive FFT for power-of-two N
class _Complex {
  double re, im;
  _Complex(this.re, this.im);
}

List<_Complex> _fft(List<_Complex> x) {
  final n = x.length;
  if (n == 1) return [x[0]];
  if (n % 2 != 0) {
    // fallback to DFT
    return _dft(x);
  }
  final even = List<_Complex>.generate(n ~/ 2, (i) => x[2 * i]);
  final odd = List<_Complex>.generate(n ~/ 2, (i) => x[2 * i + 1]);
  final Fe = _fft(even);
  final Fo = _fft(odd);
  final out = List<_Complex>.generate(n, (i) => _Complex(0, 0));
  for (int k = 0; k < n ~/ 2; k++) {
    final expRe = cos(-2 * pi * k / n);
    final expIm = sin(-2 * pi * k / n);
    final tre = expRe * Fo[k].re - expIm * Fo[k].im;
    final tim = expRe * Fo[k].im + expIm * Fo[k].re;
    out[k] = _Complex(Fe[k].re + tre, Fe[k].im + tim);
    out[k + n ~/ 2] = _Complex(Fe[k].re - tre, Fe[k].im - tim);
  }
  return out;
}

List<_Complex> _dft(List<_Complex> x) {
  final n = x.length;
  final out = List<_Complex>.generate(n, (i) => _Complex(0, 0));
  for (int k = 0; k < n; k++) {
    double sumRe = 0.0, sumIm = 0.0;
    for (int t = 0; t < n; t++) {
      final angle = -2 * pi * t * k / n;
      final cosA = cos(angle);
      final sinA = sin(angle);
      sumRe += x[t].re * cosA - x[t].im * sinA;
      sumIm += x[t].re * sinA + x[t].im * cosA;
    }
    out[k] = _Complex(sumRe, sumIm);
  }
  return out;
}

// zero-pad to next power of two
List<_Complex> _toComplexPadded(List<double> y) {
  int n = 1;
  while (n < y.length) n <<= 1;
  final out = List<_Complex>.generate(n, (i) => _Complex(0, 0));
  for (int i = 0; i < y.length; i++) out[i].re = y[i];
  return out;
}

AudioFeatures analyzeFromSamples(List<double> samples, int sr,
    {int bandStepHz = 1000, int bandMaxHz = 8000}) {
  final N = samples.length;
  final peak = samples.isEmpty ? 0.0 : samples.map((e) => e.abs()).reduce(max);
  final rms = samples.isEmpty
      ? 0.0
      : sqrt(samples.map((e) => e * e).reduce((a, b) => a + b) / N);
  final rmsDbfs = 20 * log(max(rms, _eps)) / ln10;
  final peakDbfs = 20 * log(max(peak, _eps)) / ln10;

  // FFT
  final comp = _toComplexPadded(samples);
  final spec = _fft(comp);
  final half = spec.length ~/ 2;
  final mags = List<double>.generate(half, (i) => sqrt(spec[i].re * spec[i].re + spec[i].im * spec[i].im));
  final freqs = List<double>.generate(half, (i) => i * sr / spec.length);
  final totalMag = mags.fold(0.0, (a, b) => a + b) + _eps;
  double centroid = 0.0;
  for (int i = 0; i < half; i++) centroid += freqs[i] * mags[i];
  centroid = centroid / totalMag;

  // ear_mask 1k-5k, hi_mask >3k
  double earE = 0.0, hiE = 0.0;
  for (int i = 0; i < half; i++) {
    final f = freqs[i];
    final m = mags[i];
    if (f >= 1000 && f <= 5000) earE += m;
    if (f > 3000) hiE += m;
  }
  final loudSone = 10.0 * (earE / totalMag);
  final sharpness = (hiE / totalMag) * loudSone;

  // band peaks
  final bandPeaks = <String, double>{};
  final int hi = min(bandMaxHz, freqs.isNotEmpty ? freqs.last.toInt() : 0);
  for (int lo = 0; lo < hi; lo += bandStepHz) {
    final hiBand = lo + bandStepHz;
    final key = 'band_${(lo / 1000).floor()}k_${(hiBand / 1000).floor()}k_peak_amp';
    double bestAmp = 0.0;
    for (int i = 0; i < half; i++) {
      final f = freqs[i];
      if (f >= lo && f < hiBand) {
        if (mags[i] > bestAmp) bestAmp = mags[i];
      }
    }
    bandPeaks[key] = bestAmp;
  }
  final b23 = bandPeaks['band_2k_3k_peak_amp'] ?? 0.0;
  final b34 = bandPeaks['band_3k_4k_peak_amp'] ?? 0.0;
  final highbandAmp = (b23 + b34) / 2.0;

  return AudioFeatures(
    rmsDbfs: rmsDbfs,
    spectralCentroid: centroid,
    sharpnessHfxLoud: sharpness,
    highbandAmp: highbandAmp,
    peakDbfs: peakDbfs,
    bandPeaks: bandPeaks,
  );
}

// Weighted z^2 distance
double z2DistanceWeighted(Map<String, double> x, Map<String, double> mu,
    Map<String, double> sd, Map<String, double> weights) {
  double total = 0.0;
  int used = 0;
  weights.forEach((k, w) {
    if (!x.containsKey(k) || !mu.containsKey(k) || !sd.containsKey(k)) return;
    final xv = x[k]!;
    final mv = mu[k]!;
    final sv = sd[k]! > 1e-12 ? sd[k]! : 1e-12;
    final z = (xv - mv) / sv;
    total += w * z * z;
    used += 1;
  });
  return used > 0 ? total : double.infinity;
}

// Simple CSV loader for reference stats (expects columns with feature names)
Map<String, dynamic> loadReferenceStats(String csvPath) {
  final file = File(csvPath);
  if (!file.existsSync()) return {};
  final lines = file.readAsLinesSync();
  final rows = <Map<String, String>>[];
  if (lines.isEmpty) return {};
  final header = lines[0].split(',').map((s) => s.trim()).toList();
  for (int i = 1; i < lines.length; i++) {
    final cols = lines[i].split(',');
    if (cols.isEmpty) continue;
    final title = cols[0].toString();
    if (title.startsWith('__')) continue;
    final map = <String, String>{};
    for (int j = 0; j < header.length && j < cols.length; j++) {
      map[header[j]] = cols[j];
    }
    rows.add(map);
  }
  if (rows.isEmpty) return {};
  // compute mean and std for required features
  final need = ['rms_dbfs','spectral_centroid','sharpness_hfxloud','band_2k_3k_peak_amp','band_3k_4k_peak_amp','peak_dbfs'];
  final mu = <String,double>{};
  final sd = <String,double>{};
  for (final k in need) {
    final vals = <double>[];
    for (final r in rows) {
      if (r.containsKey(k)) {
        final v = double.tryParse(r[k]!.toString());
        if (v != null) vals.add(v);
      }
    }
    if (vals.isEmpty) { mu[k]= double.nan; sd[k]= double.nan; continue; }
    final mean = vals.reduce((a,b)=>a+b)/vals.length;
    double variance = 0.0;
    for (final v in vals) variance += (v-mean)*(v-mean);
    variance = variance / (vals.length - 1 > 0 ? vals.length -1 : vals.length);
    mu[k]=mean; sd[k]=sqrt(max(variance, _eps));
  }
  return {'mu':mu, 'sd':sd};
}

// Rule-based scoring for audio features
Map<String, dynamic> ruleBasedScore(AudioFeatures features, Map<String, Map<String, double>> intervals, double perFeatureScore) {
  double totalScore = 0.0;
  Map<String, bool> passes = {};

  intervals.forEach((feature, cfg) {
    double value;
    if (feature == 'highband_amp') {
      value = ((features.bandPeaks['band_2k_3k_peak_amp'] ?? 0.0) + (features.bandPeaks['band_3k_4k_peak_amp'] ?? 0.0)) / 2.0;
    } else {
      value = features.toMap()[feature] ?? double.nan;
    }

    double low = cfg['low'] ?? double.negativeInfinity;
    double high = cfg['high'] ?? double.infinity;
    double weight = cfg['weight'] ?? 1.0;

    bool passed = !value.isNaN && value >= low && value <= high;
    if (passed) {
      totalScore += perFeatureScore * weight;
    }
    passes[feature] = passed;
  });

  return {'totalScore': totalScore, 'passes': passes};
}

// Classify audio features as good or bad
String classifyAudioFeatures(AudioFeatures features, Map<String, Map<String, double>> intervals, double perFeatureScore, double thresholdScore) {
  final result = ruleBasedScore(features, intervals, perFeatureScore);
  return result['totalScore'] >= thresholdScore ? 'good' : 'bad';
}

// Process CSV rows and classify
List<Map<String, dynamic>> processCsvRows(List<Map<String, String>> rows, Map<String, Map<String, double>> intervals, double perFeatureScore, double thresholdScore) {
  List<Map<String, dynamic>> results = [];

  for (final row in rows) {
    final features = AudioFeatures(
      rmsDbfs: double.tryParse(row['rms_dbfs'] ?? '0') ?? 0.0,
      spectralCentroid: double.tryParse(row['spectral_centroid'] ?? '0') ?? 0.0,
      sharpnessHfxLoud: double.tryParse(row['sharpness_hfxloud'] ?? '0') ?? 0.0,
      highbandAmp: 0.0, // Calculated later
      peakDbfs: double.tryParse(row['peak_dbfs'] ?? '0') ?? 0.0,
      bandPeaks: {
        'band_2k_3k_peak_amp': double.tryParse(row['band_2k_3k_peak_amp'] ?? '0') ?? 0.0,
        'band_3k_4k_peak_amp': double.tryParse(row['band_3k_4k_peak_amp'] ?? '0') ?? 0.0,
      },
    );

    final classification = classifyAudioFeatures(features, intervals, perFeatureScore, thresholdScore);
    results.add({
      'features': features.toMap(),
      'classification': classification,
    });
  }

  return results;
}
