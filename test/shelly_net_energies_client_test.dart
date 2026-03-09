import 'dart:convert';

import 'package:flutter_shelly/flutter_shelly.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'falls back from Switch.GetNetEnergies to EMData.GetNetEnergies',
    () async {
      final client = _FakeNetEnergiesClient();

      final data = await client.getNetEnergies(
        startDate: DateTime(2026, 1, 1, 0, 0),
        endDate: DateTime(2026, 1, 1, 2, 0),
        period: ShellyEnergyPeriod.hourly,
        componentId: 0,
      );

      expect(client.calledMethods.take(2), [
        'Switch.GetNetEnergies',
        'EMData.GetNetEnergies',
      ]);
      expect(data.metricKey, 'net_act_energy');
      expect(data.points.length, 2);
      expect(data.points.first.energyWh, 1.5);
    },
  );

  test('reuses successful namespace for all periods', () async {
    final client = _FakeNetEnergiesClient();

    final byPeriod = await client.getNetEnergiesForAllPeriods(
      startDate: DateTime(2026, 1, 1, 0, 0),
      endDate: DateTime(2026, 1, 1, 2, 0),
      componentId: 0,
    );

    expect(byPeriod.keys.length, ShellyEnergyPeriod.values.length);
    expect(client.calledMethods.first, 'Switch.GetNetEnergies');
    expect(client.calledMethods[1], 'EMData.GetNetEnergies');
    expect(
      client.calledMethods.skip(2).every((m) => m == 'EMData.GetNetEnergies'),
      isTrue,
    );
  });
}

class _FakeNetEnergiesClient extends ShellyApiClient {
  _FakeNetEnergiesClient() : super(host: '127.0.0.1');

  final List<String> calledMethods = [];

  @override
  Future<ShellyApiResponse> post(
    Uri url, {
    Map<String, String>? headers,
    required String body,
  }) async {
    final request = jsonDecode(body) as Map<String, dynamic>;
    final method = request['method'] as String;
    final id = request['id'];
    calledMethods.add(method);

    if (method == 'Switch.GetNetEnergies') {
      return _errorResponse(
        id: id,
        code: 404,
        message: 'No handler for Switch.GetNetEnergies',
      );
    }

    if (method == 'EMData.GetNetEnergies') {
      return _successResponse(
        id: id,
        result: {
          'keys': ['net_act_energy'],
          'data': [
            {
              'ts': DateTime(2026, 1, 1, 0, 0).millisecondsSinceEpoch ~/ 1000,
              'period': 3600,
              'values': [
                [1.5],
                [2.0],
              ],
            },
          ],
        },
      );
    }

    return _errorResponse(id: id, code: 404, message: 'No handler for $method');
  }

  ShellyApiResponse _successResponse({
    required Object? id,
    required Map<String, dynamic> result,
  }) {
    return ShellyApiResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode({'id': id, 'src': 'test', 'result': result}),
    );
  }

  ShellyApiResponse _errorResponse({
    required Object? id,
    required int code,
    required String message,
  }) {
    return ShellyApiResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode({
        'id': id,
        'src': 'test',
        'error': {'code': code, 'message': message},
      }),
    );
  }
}
