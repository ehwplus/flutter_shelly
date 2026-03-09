enum ShellyEnergyPeriod {
  fiveMinutes(300, '300s'),
  fifteenMinutes(900, '900s'),
  thirtyMinutes(1800, '1800s'),
  hourly(3600, '3600s');

  const ShellyEnergyPeriod(this.seconds, this.apiName);

  final int seconds;
  final String apiName;
}

enum ShellyEnergyDataIntervalType {
  fiveMinutes,
  fifteenMinutes,
  thirtyMinutes,
  hourly,
  activity,
}

class ShellyEnergyDataInterval {
  const ShellyEnergyDataInterval._({
    required this.intervalType,
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.componentId,
    required this.rpcNamespace,
    required this.addKeys,
    this.metricKey,
  });

  factory ShellyEnergyDataInterval.fiveMinutes({
    required DateTime startDate,
    required DateTime endDate,
    int componentId = 0,
    String rpcNamespace = 'EMData',
    bool addKeys = true,
    String? metricKey,
  }) {
    return _build(
      intervalType: ShellyEnergyDataIntervalType.fiveMinutes,
      period: ShellyEnergyPeriod.fiveMinutes,
      startDate: startDate,
      endDate: endDate,
      componentId: componentId,
      rpcNamespace: rpcNamespace,
      addKeys: addKeys,
      metricKey: metricKey,
    );
  }

  factory ShellyEnergyDataInterval.fifteenMinutes({
    required DateTime startDate,
    required DateTime endDate,
    int componentId = 0,
    String rpcNamespace = 'EMData',
    bool addKeys = true,
    String? metricKey,
  }) {
    return _build(
      intervalType: ShellyEnergyDataIntervalType.fifteenMinutes,
      period: ShellyEnergyPeriod.fifteenMinutes,
      startDate: startDate,
      endDate: endDate,
      componentId: componentId,
      rpcNamespace: rpcNamespace,
      addKeys: addKeys,
      metricKey: metricKey,
    );
  }

  factory ShellyEnergyDataInterval.thirtyMinutes({
    required DateTime startDate,
    required DateTime endDate,
    int componentId = 0,
    String rpcNamespace = 'EMData',
    bool addKeys = true,
    String? metricKey,
  }) {
    return _build(
      intervalType: ShellyEnergyDataIntervalType.thirtyMinutes,
      period: ShellyEnergyPeriod.thirtyMinutes,
      startDate: startDate,
      endDate: endDate,
      componentId: componentId,
      rpcNamespace: rpcNamespace,
      addKeys: addKeys,
      metricKey: metricKey,
    );
  }

  factory ShellyEnergyDataInterval.hourly({
    required DateTime startDate,
    required DateTime endDate,
    int componentId = 0,
    String rpcNamespace = 'EMData',
    bool addKeys = true,
    String? metricKey,
  }) {
    return _build(
      intervalType: ShellyEnergyDataIntervalType.hourly,
      period: ShellyEnergyPeriod.hourly,
      startDate: startDate,
      endDate: endDate,
      componentId: componentId,
      rpcNamespace: rpcNamespace,
      addKeys: addKeys,
      metricKey: metricKey,
    );
  }

  factory ShellyEnergyDataInterval.activity({
    required DateTime startDate,
    required DateTime endDate,
    ShellyEnergyPeriod period = ShellyEnergyPeriod.fiveMinutes,
    int componentId = 0,
    String rpcNamespace = 'EMData',
    bool addKeys = true,
    String? metricKey,
  }) {
    return _build(
      intervalType: ShellyEnergyDataIntervalType.activity,
      period: period,
      startDate: startDate,
      endDate: endDate,
      componentId: componentId,
      rpcNamespace: rpcNamespace,
      addKeys: addKeys,
      metricKey: metricKey,
    );
  }

  static ShellyEnergyDataInterval _build({
    required ShellyEnergyDataIntervalType intervalType,
    required ShellyEnergyPeriod period,
    required DateTime startDate,
    required DateTime endDate,
    required int componentId,
    required String rpcNamespace,
    required bool addKeys,
    String? metricKey,
  }) {
    final alignedStart = _alignToPeriodStart(startDate, period.seconds);
    final alignedEnd = _alignToPeriodStart(endDate, period.seconds);
    if (alignedEnd.isBefore(alignedStart)) {
      throw ArgumentError('endDate must be on or after startDate.');
    }
    if (rpcNamespace.trim().isEmpty) {
      throw ArgumentError('rpcNamespace must not be empty.');
    }

    return ShellyEnergyDataInterval._(
      intervalType: intervalType,
      period: period,
      startDate: alignedStart,
      endDate: alignedEnd,
      componentId: componentId,
      rpcNamespace: rpcNamespace,
      addKeys: addKeys,
      metricKey: metricKey,
    );
  }

  final ShellyEnergyDataIntervalType intervalType;
  final ShellyEnergyPeriod period;
  final DateTime startDate;
  final DateTime endDate;
  final int componentId;
  final String rpcNamespace;
  final bool addKeys;
  final String? metricKey;

  Duration get periodDuration => Duration(seconds: period.seconds);

  String get rpcMethod => '$rpcNamespace.GetData';

  Map<String, dynamic> toParams() {
    return {
      'id': componentId,
      'ts': _toUnixSeconds(startDate),
      'end_ts': _toUnixSeconds(endDate),
      'period': period.seconds,
      if (!addKeys) 'add_keys': false,
    };
  }

  static DateTime _alignToPeriodStart(DateTime date, int periodSeconds) {
    final epochSeconds = date.millisecondsSinceEpoch ~/ 1000;
    final aligned = (epochSeconds ~/ periodSeconds) * periodSeconds;
    return DateTime.fromMillisecondsSinceEpoch(
      aligned * 1000,
      isUtc: date.isUtc,
    );
  }

  static int _toUnixSeconds(DateTime date) {
    return date.millisecondsSinceEpoch ~/ 1000;
  }
}

class ShellyEnergyData {
  const ShellyEnergyData({
    required this.intervalType,
    required this.period,
    required this.metricKey,
    required this.points,
    required this.availableKeys,
  });

  factory ShellyEnergyData.fromJson(
    Map<String, dynamic> json, {
    required ShellyEnergyDataInterval interval,
  }) {
    final legacy = _parseLegacyPoints(json, interval: interval);
    if (legacy != null) {
      return ShellyEnergyData(
        intervalType: interval.intervalType,
        period: interval.period,
        metricKey: interval.metricKey ?? 'value',
        points: legacy,
        availableKeys: const ['value'],
      ).trimToNow();
    }

    final keys = _parseStringList(json['keys']);
    final resolvedMetricKey = _resolveMetricKey(
      keys,
      preferredKey: interval.metricKey,
    );
    final resolvedMetricIndex = _resolveMetricIndex(keys, resolvedMetricKey);

    final points = <ShellyEnergyDataPoint>[];
    final rawData = json['data'];
    if (rawData is List) {
      for (final item in rawData) {
        final itemMap = _asMap(item);
        final baseTs = _parseInt(itemMap['ts']);
        final recordPeriod =
            _parseInt(itemMap['period']) ?? interval.period.seconds;
        final rawValues = itemMap['values'];

        if (rawValues is! List) {
          continue;
        }

        for (var index = 0; index < rawValues.length; index += 1) {
          final row = rawValues[index];
          final numericRow = _parseDoubleRow(row);
          if (numericRow.isEmpty) {
            continue;
          }

          final value = resolvedMetricIndex < numericRow.length
              ? numericRow[resolvedMetricIndex]
              : numericRow.first;

          final start = _buildPointStart(
            baseTs: baseTs,
            rowIndex: index,
            periodSeconds: recordPeriod,
            fallbackStart: interval.startDate,
          );
          points.add(ShellyEnergyDataPoint(start: start, energyWh: value));
        }
      }
    }

    points.sort((a, b) => a.start.compareTo(b.start));

    return ShellyEnergyData(
      intervalType: interval.intervalType,
      period: interval.period,
      metricKey: resolvedMetricKey,
      points: points,
      availableKeys: keys,
    ).trimToNow();
  }

  final ShellyEnergyDataIntervalType intervalType;
  final ShellyEnergyPeriod period;
  final String metricKey;
  final List<ShellyEnergyDataPoint> points;
  final List<String> availableKeys;

  ShellyEnergyData trimToNow({DateTime? now}) {
    final effectiveNow = now ?? DateTime.now();
    final filtered = points
        .where((point) => !point.start.isAfter(effectiveNow))
        .toList(growable: false);
    if (filtered.length == points.length) {
      return this;
    }
    return ShellyEnergyData(
      intervalType: intervalType,
      period: period,
      metricKey: metricKey,
      points: filtered,
      availableKeys: availableKeys,
    );
  }

  List<ShellyEnergyActivity> activities({
    double minPowerW = 2,
    Duration? maxDuration,
    Duration? minGap,
  }) {
    if (points.isEmpty) {
      return const [];
    }
    if (minPowerW < 0) {
      throw ArgumentError('minPowerW must be >= 0.');
    }

    final intervalDuration = Duration(seconds: period.seconds);
    final minEnergyWh = minPowerW * (period.seconds / 3600.0);

    final effectiveMaxDuration = _resolveMaxDuration(maxDuration);
    final maxPoints = effectiveMaxDuration == null
        ? null
        : _durationToPoints(effectiveMaxDuration, intervalDuration);

    final effectiveMinGap =
        minGap ??
        (intervalType == ShellyEnergyDataIntervalType.activity
            ? intervalDuration
            : null);
    final minGapPoints = effectiveMinGap == null
        ? 0
        : _durationToPointsCeil(effectiveMinGap, intervalDuration);

    final sortedPoints = [...points]
      ..sort((a, b) => a.start.compareTo(b.start));

    final activities = <ShellyEnergyActivity>[];
    int? currentStartIndex;
    var gapCount = minGapPoints;
    var sawGap = false;

    for (var index = 0; index < sortedPoints.length; index += 1) {
      final point = sortedPoints[index];
      final hasEnergy = point.energyWh >= minEnergyWh;

      if (index > 0) {
        final previous = sortedPoints[index - 1];
        final diff = point.start.difference(previous.start);
        if (diff > intervalDuration) {
          if (currentStartIndex != null) {
            activities.add(
              _buildActivity(
                sortedPoints,
                currentStartIndex,
                index,
                intervalDuration,
              ),
            );
            currentStartIndex = null;
          }
          gapCount = minGapPoints;
          sawGap = true;
        }
      }

      if (currentStartIndex != null) {
        if (!hasEnergy) {
          activities.add(
            _buildActivity(
              sortedPoints,
              currentStartIndex,
              index,
              intervalDuration,
            ),
          );
          currentStartIndex = null;
          gapCount = 1;
          if (gapCount >= minGapPoints) {
            sawGap = true;
          }
          continue;
        }

        if (maxPoints != null) {
          final length = index - currentStartIndex + 1;
          if (length >= maxPoints) {
            activities.add(
              _buildActivity(
                sortedPoints,
                currentStartIndex,
                index + 1,
                intervalDuration,
              ),
            );
            currentStartIndex = null;
            gapCount = 0;
            continue;
          }
        }
        continue;
      }

      if (hasEnergy) {
        if (gapCount >= minGapPoints) {
          currentStartIndex = index;
        }
        continue;
      }

      if (gapCount < minGapPoints) {
        gapCount += 1;
        if (gapCount >= minGapPoints) {
          sawGap = true;
        }
      } else {
        sawGap = true;
      }
    }

    if (currentStartIndex != null) {
      activities.add(
        _buildActivity(
          sortedPoints,
          currentStartIndex,
          sortedPoints.length,
          intervalDuration,
        ),
      );
    }

    if (intervalType == ShellyEnergyDataIntervalType.activity && !sawGap) {
      return const [];
    }

    return activities;
  }

  ShellyEnergyActivity _buildActivity(
    List<ShellyEnergyDataPoint> sortedPoints,
    int startIndex,
    int endExclusiveIndex,
    Duration intervalDuration,
  ) {
    final start = sortedPoints[startIndex].start;
    final end = sortedPoints[endExclusiveIndex - 1].start.add(intervalDuration);

    var energyWh = 0.0;
    for (var index = startIndex; index < endExclusiveIndex; index += 1) {
      energyWh += sortedPoints[index].energyWh;
    }

    return ShellyEnergyActivity(start: start, end: end, energyWh: energyWh);
  }

  Duration? _resolveMaxDuration(Duration? maxDuration) {
    final resolved =
        maxDuration ??
        (intervalType == ShellyEnergyDataIntervalType.activity
            ? const Duration(hours: 12)
            : null);
    if (resolved != null && resolved > const Duration(hours: 24)) {
      throw ArgumentError('maxDuration must not exceed 24 hours.');
    }
    return resolved;
  }

  static int _durationToPoints(Duration duration, Duration intervalDuration) {
    final points = duration.inSeconds ~/ intervalDuration.inSeconds;
    if (points < 1) {
      throw ArgumentError('Duration must be at least one interval.');
    }
    return points;
  }

  static int _durationToPointsCeil(
    Duration duration,
    Duration intervalDuration,
  ) {
    final points = (duration.inMilliseconds / intervalDuration.inMilliseconds)
        .ceil();
    if (points < 1) {
      throw ArgumentError('Duration must be at least one interval.');
    }
    return points;
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value.map((item) => item.toString()).toList(growable: false);
  }

  static DateTime _buildPointStart({
    required int? baseTs,
    required int rowIndex,
    required int periodSeconds,
    required DateTime fallbackStart,
  }) {
    if (baseTs != null && baseTs > 0) {
      return DateTime.fromMillisecondsSinceEpoch(
        (baseTs + (rowIndex * periodSeconds)) * 1000,
      );
    }
    return fallbackStart.add(Duration(seconds: periodSeconds * rowIndex));
  }

  static String _resolveMetricKey(List<String> keys, {String? preferredKey}) {
    if (preferredKey != null && preferredKey.isNotEmpty) {
      return preferredKey;
    }

    const candidates = [
      'total_act_energy',
      'a_total_act_energy',
      'b_total_act_energy',
      'c_total_act_energy',
      'energy',
      'total',
    ];

    for (final candidate in candidates) {
      if (keys.contains(candidate)) {
        return candidate;
      }
    }

    for (final key in keys) {
      if (key.contains('total_act_energy')) {
        return key;
      }
    }

    for (final key in keys) {
      if (key.contains('energy')) {
        return key;
      }
    }

    return keys.isNotEmpty ? keys.first : 'value';
  }

  static int _resolveMetricIndex(List<String> keys, String metricKey) {
    final index = keys.indexOf(metricKey);
    return index >= 0 ? index : 0;
  }

  static List<ShellyEnergyDataPoint>? _parseLegacyPoints(
    Map<String, dynamic> json, {
    required ShellyEnergyDataInterval interval,
  }) {
    final rawValues = json['values'];
    if (rawValues is List && rawValues.isNotEmpty && rawValues.first is Map) {
      final points = <ShellyEnergyDataPoint>[];
      for (final item in rawValues) {
        final map = _asMap(item);
        final ts = _parseInt(map['ts']);
        final value = _parseDouble(map['value']);
        if (ts == null || value == null) {
          continue;
        }
        points.add(
          ShellyEnergyDataPoint(
            start: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
            energyWh: value,
          ),
        );
      }
      return points;
    }

    if (rawValues is List) {
      final points = <ShellyEnergyDataPoint>[];
      for (var index = 0; index < rawValues.length; index += 1) {
        final value = _parseDouble(rawValues[index]);
        if (value == null) {
          continue;
        }
        final start = interval.startDate.add(
          Duration(seconds: interval.period.seconds * index),
        );
        points.add(ShellyEnergyDataPoint(start: start, energyWh: value));
      }
      return points;
    }

    return null;
  }

  static List<double> _parseDoubleRow(dynamic row) {
    if (row is! List) {
      return const [];
    }
    return row.map((value) => _parseDouble(value) ?? 0).toList(growable: false);
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }

  static int? _parseInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _parseDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }
}

class ShellyEnergyDataPoint {
  const ShellyEnergyDataPoint({required this.start, required this.energyWh});

  final DateTime start;
  final double energyWh;
}

class ShellyEnergyActivity {
  const ShellyEnergyActivity({
    required this.start,
    required this.end,
    required this.energyWh,
  });

  final DateTime start;
  final DateTime end;
  final double energyWh;
}
