import 'package:flutter_shelly/flutter_shelly.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses EMData keys/data format into points', () {
    final interval = ShellyEnergyDataInterval.fiveMinutes(
      startDate: DateTime(2026, 1, 1, 0, 0),
      endDate: DateTime(2026, 1, 1, 0, 15),
    );

    final data = ShellyEnergyData.fromJson({
      'keys': ['a_total_act_energy', 'a_max_voltage'],
      'data': [
        {
          'ts': interval.startDate.millisecondsSinceEpoch ~/ 1000,
          'period': 300,
          'values': [
            [1.2, 231.0],
            [2.3, 232.0],
            [3.4, 233.0],
          ],
        },
      ],
    }, interval: interval);

    expect(data.metricKey, 'a_total_act_energy');
    expect(data.points.length, 3);
    expect(data.points[0].start, DateTime(2026, 1, 1, 0, 0));
    expect(data.points[1].start, DateTime(2026, 1, 1, 0, 5));
    expect(data.points[2].energyWh, 3.4);
  });

  test('uses explicit metric key', () {
    final interval = ShellyEnergyDataInterval.fiveMinutes(
      startDate: DateTime(2026, 1, 1, 0, 0),
      endDate: DateTime(2026, 1, 1, 0, 10),
      metricKey: 'a_max_voltage',
    );

    final data = ShellyEnergyData.fromJson({
      'keys': ['a_total_act_energy', 'a_max_voltage'],
      'data': [
        {
          'ts': interval.startDate.millisecondsSinceEpoch ~/ 1000,
          'period': 300,
          'values': [
            [1.2, 231.0],
            [2.3, 232.0],
          ],
        },
      ],
    }, interval: interval);

    expect(data.metricKey, 'a_max_voltage');
    expect(data.points[0].energyWh, 231.0);
    expect(data.points[1].energyWh, 232.0);
  });

  test('builds activity windows from five-minute data', () {
    final interval = ShellyEnergyDataInterval.activity(
      startDate: DateTime(2026, 1, 1, 0, 0),
      endDate: DateTime(2026, 1, 1, 0, 30),
    );

    final data = ShellyEnergyData.fromJson({
      'values': [0.0, 0.5, 0.5, 0.0, 0.3, 0.4, 0.0],
    }, interval: interval);

    final activities = data.activities();
    expect(activities.length, 2);
    expect(activities[0].start, DateTime(2026, 1, 1, 0, 5));
    expect(activities[0].end, DateTime(2026, 1, 1, 0, 15));
    expect(activities[1].start, DateTime(2026, 1, 1, 0, 20));
    expect(activities[1].end, DateTime(2026, 1, 1, 0, 30));
  });

  test('returns no activities for constant draw in activity mode', () {
    final interval = ShellyEnergyDataInterval.activity(
      startDate: DateTime(2026, 1, 1, 0, 0),
      endDate: DateTime(2026, 1, 1, 0, 20),
    );

    final data = ShellyEnergyData.fromJson({
      'values': [0.4, 0.4, 0.4, 0.4, 0.4],
    }, interval: interval);

    expect(data.activities(), isEmpty);
  });

  test('rejects maxDuration greater than 24 hours', () {
    final interval = ShellyEnergyDataInterval.activity(
      startDate: DateTime(2026, 1, 1, 0, 0),
      endDate: DateTime(2026, 1, 1, 0, 20),
    );

    final data = ShellyEnergyData.fromJson({
      'values': [0.4, 0.4, 0.4, 0.0, 0.4],
    }, interval: interval);

    expect(
      () => data.activities(maxDuration: const Duration(hours: 25)),
      throwsArgumentError,
    );
  });

  test('aligns interval bounds to selected period', () {
    final interval = ShellyEnergyDataInterval.hourly(
      startDate: DateTime(2026, 1, 1, 0, 59, 59),
      endDate: DateTime(2026, 1, 1, 2, 59, 59),
    );

    final params = interval.toParams();

    expect(interval.startDate, DateTime(2026, 1, 1, 0, 0));
    expect(interval.endDate, DateTime(2026, 1, 1, 2, 0));
    expect(params['period'], 3600);
  });
}
