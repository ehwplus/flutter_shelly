import 'package:flutter_shelly/flutter_shelly.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports Shelly energy periods', () {
    expect(ShellyEnergyPeriod.values, isNotEmpty);
  });
}
