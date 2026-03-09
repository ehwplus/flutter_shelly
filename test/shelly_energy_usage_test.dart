import 'package:flutter_shelly/flutter_shelly.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses aenergy.by_minute and converts mWh to Wh', () {
    final usage = ShellyEnergyUsage.fromJson({
      'output': true,
      'apower': 42.7,
      'aenergy': {
        'total': 1234.5,
        'minute_ts': 1_700_000_000,
        'by_minute': [120.0, 80.5, 10.0],
      },
    }, id: 2);

    expect(usage.id, 2);
    expect(usage.activePowerW, 42.7);
    expect(usage.totalActiveEnergyWh, 1234.5);
    expect(usage.byMinuteMilliWattHours, [120.0, 80.5, 10.0]);
    expect(usage.byMinuteWh[0], closeTo(0.12, 0.000001));
    expect(usage.byMinuteWh[1], closeTo(0.0805, 0.000001));
    expect(usage.byMinuteWh[2], closeTo(0.01, 0.000001));
    expect(usage.activeEnergySeries['by_minute'], [120.0, 80.5, 10.0]);
  });

  test('supports anergy fallback keys', () {
    final usage = ShellyEnergyUsage.fromJson({
      'output': false,
      'apower': 0,
      'anergy': {
        'total': 77,
        'minute_ts': 123,
        'by_minute': [5, 6, 7],
      },
    }, id: 0);

    expect(usage.totalActiveEnergyWh, 77);
    expect(usage.minuteTimestamp, 123);
    expect(usage.byMinuteMilliWattHours, [5, 6, 7]);
  });
}
