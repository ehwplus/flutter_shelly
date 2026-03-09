class ShellyEnergyUsage {
  const ShellyEnergyUsage({
    required this.id,
    required this.output,
    required this.activePowerW,
    required this.totalActiveEnergyWh,
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
    final activeEnergy = _asMap(json['aenergy']);
    final returnedEnergy = _asMap(json['ret_aenergy']);
    return ShellyEnergyUsage(
      id: id,
      output: json['output'] == true,
      activePowerW: _parseDouble(json['apower']) ?? 0,
      totalActiveEnergyWh: _parseDouble(activeEnergy['total']) ?? 0,
      byMinuteWh: _parseDoubleList(activeEnergy['by_minute']),
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

  static double? _parseTemperature(dynamic value) {
    final map = _asMap(value);
    return _parseDouble(map['tC']);
  }
}
