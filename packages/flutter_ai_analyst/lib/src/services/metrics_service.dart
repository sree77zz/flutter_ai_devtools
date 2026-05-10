import 'dart:collection';

/// Tracks internal analyst-engine counters.
///
/// Intentionally kept separate from the Flutter performance metrics collected
/// by [FrameCollector] — this measures the overhead of the analyst itself.
class MetricsService {
  MetricsService._();
  static final MetricsService instance = MetricsService._();

  final _counters = <String, int>{};
  final _gauges = <String, double>{};
  final _histograms = <String, Queue<double>>{};

  static const int _histogramMaxSize = 100;

  void increment(String key, [int by = 1]) =>
      _counters[key] = (_counters[key] ?? 0) + by;

  void gauge(String key, double value) => _gauges[key] = value;

  void record(String key, double value) {
    final q = _histograms.putIfAbsent(key, Queue.new);
    if (q.length >= _histogramMaxSize) q.removeFirst();
    q.addLast(value);
  }

  double? average(String key) {
    final q = _histograms[key];
    if (q == null || q.isEmpty) return null;
    return q.reduce((a, b) => a + b) / q.length;
  }

  Map<String, dynamic> snapshot() => {
        'counters': Map.unmodifiable(_counters),
        'gauges': Map.unmodifiable(_gauges),
        'histogramAverages': {
          for (final e in _histograms.entries)
            e.key: e.value.isEmpty
                ? 0.0
                : e.value.reduce((a, b) => a + b) / e.value.length,
        },
      };

  void reset() {
    _counters.clear();
    _gauges.clear();
    _histograms.clear();
  }
}
