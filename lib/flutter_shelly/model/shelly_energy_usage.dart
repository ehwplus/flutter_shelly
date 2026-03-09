class ShellyEnergyUsage {
  const ShellyEnergyUsage({
    required this.id,
    required this.output,
    required this.activePowerW,
    required this.totalActiveEnergyWh,
    required this.activeEnergySeries,
    required this.byMinuteMilliWattHours,
    required this.byMinuteWh,
    required this.minuteTimestamp,
    this.totalReturnedEnergyWh,
    this.currentA,
    this.voltageV,
    this.frequencyHz,
    this.powerFactor,
    this.temperatureC,
  });

  factory ShellyEnergyUsage.fromJson(
    Map<String, dynamic> json, {
    required int id,
  }) {
    final activeEnergy = _resolveEnergyMap(json, preferredKey: 'aenergy');
    final returnedEnergy = _resolveEnergyMap(json, preferredKey: 'ret_aenergy');
    final activeEnergySeries = _parseSeriesMap(activeEnergy);
    final byMinuteMilliWattHours =
        activeEnergySeries['by_minute'] ??
        _parseDoubleList(activeEnergy['by_minute']);

    return ShellyEnergyUsage(
      id: id,
      output: json['output'] == true,
      activePowerW: _parseDouble(json['apower']) ?? 0,
      totalActiveEnergyWh: _parseDouble(activeEnergy['total']) ?? 0,
      activeEnergySeries: activeEnergySeries,
      byMinuteMilliWattHours: byMinuteMilliWattHours,
      byMinuteWh: byMinuteMilliWattHours
          .map((value) => value / 1000)
          .toList(growable: false),
      minuteTimestamp: _parseInt(activeEnergy['minute_ts']) ?? 0,
      totalReturnedEnergyWh: _parseDouble(returnedEnergy['total']),
      currentA: _parseDouble(json['current']),
      voltageV: _parseDouble(json['voltage']),
      frequencyHz: _parseDouble(json['freq']),
      powerFactor: _parseDouble(json['pf']),
      temperatureC: _parseTemperature(json['temperature']),
    );
  }

  final int id;
  final bool output;
  final double activePowerW;
  final double totalActiveEnergyWh;
  final Map<String, List<double>> activeEnergySeries;
  final List<double> byMinuteMilliWattHours;
  final List<double> byMinuteWh;
  final int minuteTimestamp;
  final double? totalReturnedEnergyWh;
  final double? currentA;
  final double? voltageV;
  final double? frequencyHz;
  final double? powerFactor;
  final double? temperatureC;

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }

  static Map<String, dynamic> _resolveEnergyMap(
    Map<String, dynamic> json, {
    required String preferredKey,
  }) {
    final primary = _asMap(json[preferredKey]);
    if (primary.isNotEmpty) {
      return primary;
    }

    // Some firmwares expose `anergy` instead of `aenergy`.
    final alternateKey = preferredKey.replaceFirst('aenergy', 'anergy');
    if (alternateKey != preferredKey) {
      return _asMap(json[alternateKey]);
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

  static List<double> _parseDoubleList(dynamic values) {
    if (values is! List) {
      return const [];
    }
    return values
        .map((value) => _parseDouble(value) ?? 0)
        .toList(growable: false);
  }

  static Map<String, List<double>> _parseSeriesMap(Map<String, dynamic> json) {
    final series = <String, List<double>>{};
    for (final entry in json.entries) {
      if (!entry.key.startsWith('by_')) {
        continue;
      }
      final values = _parseDoubleList(entry.value);
      if (values.isEmpty) {
        continue;
      }
      series[entry.key] = values;
    }
    return Map.unmodifiable(series);
  }

  static double? _parseTemperature(dynamic value) {
    final map = _asMap(value);
    return _parseDouble(map['tC']);
  }
}
