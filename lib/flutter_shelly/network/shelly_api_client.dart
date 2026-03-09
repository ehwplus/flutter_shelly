import 'dart:convert';
import 'dart:math';

import '../core/shelly_exception.dart';
import '../model/shelly_device_info.dart';
import '../model/shelly_energy_data.dart';
import '../model/shelly_energy_usage.dart';
import '../util/shelly_digest_auth.dart';

abstract class ShellyApiClient {
  ShellyApiClient({
    required this.host,
    this.port = 80,
    this.useHttps = false,
    this.username,
    this.password,
    this.requestSource = 'flutter_shelly',
    Random? random,
  }) : _random = random ?? Random.secure();

  final String host;
  final int port;
  final bool useHttps;
  final String? username;
  final String? password;
  final String requestSource;

  final Random _random;
  int _requestId = 1;
  ShellyDigestAuthChallenge? _authChallenge;

  bool get _hasCredentials {
    return (username?.trim().isNotEmpty ?? false) &&
        (password?.isNotEmpty ?? false);
  }

  Future<ShellyApiResponse> post(
    Uri url, {
    Map<String, String>? headers,
    required String body,
  });

  Future<ShellyDeviceInfo> getDeviceInfo() async {
    final result = await callRpc('Shelly.GetDeviceInfo');
    return ShellyDeviceInfo.fromJson(result);
  }

  Future<Map<String, dynamic>> getStatus() {
    return callRpc('Shelly.GetStatus');
  }

  Future<Map<String, dynamic>> getSwitchStatus({
    int id = 0,
    String rpcNamespace = 'Switch',
  }) {
    return callRpc('$rpcNamespace.GetStatus', params: {'id': id});
  }

  Future<void> setSwitchState(
    bool on, {
    int id = 0,
    String rpcNamespace = 'Switch',
  }) async {
    await callRpcRaw('$rpcNamespace.Set', params: {'id': id, 'on': on});
  }

  Future<ShellyEnergyUsage> getEnergyUsage({
    int id = 0,
    String rpcNamespace = 'Switch',
  }) async {
    final status = await getSwitchStatus(id: id, rpcNamespace: rpcNamespace);
    return ShellyEnergyUsage.fromJson(status, id: id);
  }

  Future<List<ShellyEnergyUsage>> getAllSwitchEnergyUsage() async {
    final status = await getStatus();
    final usages = <ShellyEnergyUsage>[];

    for (final entry in status.entries) {
      final match = RegExp(r'^switch:(\d+)$').firstMatch(entry.key);
      if (match == null) {
        continue;
      }
      final id = int.tryParse(match.group(1) ?? '');
      if (id == null) {
        continue;
      }
      final valueMap = _asMap(entry.value);
      if (valueMap.isEmpty) {
        continue;
      }
      usages.add(ShellyEnergyUsage.fromJson(valueMap, id: id));
    }

    usages.sort((a, b) => a.id.compareTo(b.id));
    return usages;
  }

  Future<List<ShellyEnergyComponent>> getEnergyComponents() async {
    final status = await getStatus();
    final components = <ShellyEnergyComponent>[];

    for (final key in status.keys) {
      final match = RegExp(
        r'^(emdata|em1data):(\d+)$',
        caseSensitive: false,
      ).firstMatch(key);
      if (match == null) {
        continue;
      }
      final namespace = _toRpcNamespace(match.group(1)!);
      final id = int.tryParse(match.group(2) ?? '');
      if (id == null) {
        continue;
      }
      components.add(ShellyEnergyComponent(rpcNamespace: namespace, id: id));
    }

    components.sort((a, b) {
      final namespaceComparison = a.rpcNamespace.compareTo(b.rpcNamespace);
      if (namespaceComparison != 0) {
        return namespaceComparison;
      }
      return a.id.compareTo(b.id);
    });

    return components;
  }

  Future<ShellyEnergyData> getEnergyData(
    ShellyEnergyDataInterval interval,
  ) async {
    final result = await callRpc(
      interval.rpcMethod,
      params: interval.toParams(),
    );
    return ShellyEnergyData.fromJson(result, interval: interval);
  }

  Future<Map<ShellyEnergyPeriod, ShellyEnergyData>> getEnergyDataForAllPeriods({
    required DateTime startDate,
    required DateTime endDate,
    int componentId = 0,
    String rpcNamespace = 'EMData',
    String? metricKey,
    bool addKeys = true,
  }) async {
    final byPeriod = <ShellyEnergyPeriod, ShellyEnergyData>{};

    for (final period in ShellyEnergyPeriod.values) {
      final interval = _intervalFromPeriod(
        period: period,
        startDate: startDate,
        endDate: endDate,
        componentId: componentId,
        rpcNamespace: rpcNamespace,
        addKeys: addKeys,
        metricKey: metricKey,
      );
      byPeriod[period] = await getEnergyData(interval);
    }

    return byPeriod;
  }

  Future<ShellyEnergyData> getNetEnergies({
    required DateTime startDate,
    required DateTime endDate,
    ShellyEnergyPeriod period = ShellyEnergyPeriod.hourly,
    int componentId = 0,
    String? rpcNamespace,
    String? metricKey,
    bool addKeys = true,
  }) async {
    final candidateNamespaces = _resolveNetEnergiesNamespaces(
      preferredRpcNamespace: rpcNamespace,
    );
    final result = await _getNetEnergiesInternal(
      period: period,
      startDate: startDate,
      endDate: endDate,
      componentId: componentId,
      metricKey: metricKey,
      addKeys: addKeys,
      candidateRpcNamespaces: candidateNamespaces,
    );
    return result.data;
  }

  Future<Map<ShellyEnergyPeriod, ShellyEnergyData>>
  getNetEnergiesForAllPeriods({
    required DateTime startDate,
    required DateTime endDate,
    int componentId = 0,
    String? rpcNamespace,
    String? metricKey,
    bool addKeys = true,
  }) async {
    final byPeriod = <ShellyEnergyPeriod, ShellyEnergyData>{};
    var candidateNamespaces = _resolveNetEnergiesNamespaces(
      preferredRpcNamespace: rpcNamespace,
    );

    for (final period in ShellyEnergyPeriod.values) {
      final result = await _getNetEnergiesInternal(
        period: period,
        startDate: startDate,
        endDate: endDate,
        componentId: componentId,
        metricKey: metricKey,
        addKeys: addKeys,
        candidateRpcNamespaces: candidateNamespaces,
      );
      byPeriod[period] = result.data;
      candidateNamespaces = [result.rpcNamespace];
    }

    return byPeriod;
  }

  Future<Map<String, dynamic>> callRpc(
    String method, {
    Map<String, dynamic>? params,
  }) async {
    final result = await callRpcRaw(method, params: params);
    if (result is Map<String, dynamic>) {
      return result;
    }
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    throw ShellyProtocolException(
      'RPC method $method returned an unexpected result type: ${result.runtimeType}.',
    );
  }

  Future<dynamic> callRpcRaw(String method, {Map<String, dynamic>? params}) {
    return _callRpcRawInternal(method, params: params, allowAuthRetry: true);
  }

  Future<dynamic> _callRpcRawInternal(
    String method, {
    Map<String, dynamic>? params,
    required bool allowAuthRetry,
  }) async {
    final payload = _buildPayload(method, params: params);

    final response = await post(
      _rpcUri(),
      headers: _defaultHeaders,
      body: jsonEncode(payload),
    );

    final responseMap = _decodeResponseBody(response.body);

    final authError = _isAuthError(response.statusCode, responseMap['error']);
    if (authError && _hasCredentials && allowAuthRetry) {
      final challenge = ShellyDigestAuth.tryParse(responseMap['error']);
      if (challenge == null) {
        throw const ShellyAuthenticationException(
          'Device requested authentication but auth challenge could not be parsed.',
        );
      }
      _authChallenge = challenge;
      return _callRpcRawInternal(method, params: params, allowAuthRetry: false);
    }

    final error = responseMap['error'];
    if (error != null) {
      _throwApiError(error, response.statusCode);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ShellyProtocolException(
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }

    return responseMap['result'];
  }

  Map<String, dynamic> _buildPayload(
    String method, {
    Map<String, dynamic>? params,
  }) {
    final payload = <String, dynamic>{
      'id': _requestId++,
      'src': requestSource,
      'method': method,
    };

    final resolvedParams = <String, dynamic>{...?params};
    if (_hasCredentials && _authChallenge != null) {
      resolvedParams['auth'] = ShellyDigestAuth.build(
        username: username!.trim(),
        password: password!,
        challenge: _authChallenge!,
        cnonce: _randomHex(16),
        random: _random,
      );
    }

    if (resolvedParams.isNotEmpty) {
      payload['params'] = resolvedParams;
    }

    return payload;
  }

  Map<String, dynamic> _decodeResponseBody(String responseBody) {
    if (responseBody.trim().isEmpty) {
      return const {};
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    throw const ShellyProtocolException(
      'Shelly response is not a JSON object.',
    );
  }

  bool _isAuthError(int statusCode, dynamic error) {
    if (statusCode == 401) {
      return true;
    }

    final errorMap = _asMap(error);
    final code = _parseInt(errorMap['code']);
    if (code == 401) {
      return true;
    }

    final message = errorMap['message']?.toString().toLowerCase() ?? '';
    return message.contains('auth') || message.contains('nonce');
  }

  Never _throwApiError(dynamic error, int httpStatusCode) {
    final errorMap = _asMap(error);
    final code = _parseInt(errorMap['code']) ?? httpStatusCode;
    final message =
        errorMap['message']?.toString() ?? 'Unknown Shelly RPC error';

    if (code == 401 || httpStatusCode == 401) {
      throw ShellyAuthenticationException(message);
    }

    throw ShellyApiException(
      code,
      message,
      payload: errorMap,
      httpStatusCode: httpStatusCode,
    );
  }

  ShellyEnergyDataInterval _intervalFromPeriod({
    required ShellyEnergyPeriod period,
    required DateTime startDate,
    required DateTime endDate,
    required int componentId,
    required String rpcNamespace,
    required bool addKeys,
    String? metricKey,
  }) {
    return switch (period) {
      ShellyEnergyPeriod.fiveMinutes => ShellyEnergyDataInterval.fiveMinutes(
        startDate: startDate,
        endDate: endDate,
        componentId: componentId,
        rpcNamespace: rpcNamespace,
        addKeys: addKeys,
        metricKey: metricKey,
      ),
      ShellyEnergyPeriod.fifteenMinutes =>
        ShellyEnergyDataInterval.fifteenMinutes(
          startDate: startDate,
          endDate: endDate,
          componentId: componentId,
          rpcNamespace: rpcNamespace,
          addKeys: addKeys,
          metricKey: metricKey,
        ),
      ShellyEnergyPeriod.thirtyMinutes =>
        ShellyEnergyDataInterval.thirtyMinutes(
          startDate: startDate,
          endDate: endDate,
          componentId: componentId,
          rpcNamespace: rpcNamespace,
          addKeys: addKeys,
          metricKey: metricKey,
        ),
      ShellyEnergyPeriod.hourly => ShellyEnergyDataInterval.hourly(
        startDate: startDate,
        endDate: endDate,
        componentId: componentId,
        rpcNamespace: rpcNamespace,
        addKeys: addKeys,
        metricKey: metricKey,
      ),
    };
  }

  Future<_ShellyNetEnergiesResult> _getNetEnergiesInternal({
    required ShellyEnergyPeriod period,
    required DateTime startDate,
    required DateTime endDate,
    required int componentId,
    required bool addKeys,
    required List<String> candidateRpcNamespaces,
    String? metricKey,
  }) async {
    Object? lastUnsupportedError;
    for (final rawNamespace in candidateRpcNamespaces) {
      final rpcNamespace = _toRpcNamespace(rawNamespace);
      final interval = _intervalFromPeriod(
        period: period,
        startDate: startDate,
        endDate: endDate,
        componentId: componentId,
        rpcNamespace: rpcNamespace,
        addKeys: addKeys,
        metricKey: metricKey,
      );
      final method = '$rpcNamespace.GetNetEnergies';
      try {
        final response = await callRpc(method, params: interval.toParams());
        final data = ShellyEnergyData.fromJson(response, interval: interval);
        return _ShellyNetEnergiesResult(data: data, rpcNamespace: rpcNamespace);
      } catch (error) {
        if (_isNoHandlerError(error, method)) {
          lastUnsupportedError = error;
          continue;
        }
        rethrow;
      }
    }

    if (lastUnsupportedError != null) {
      throw StateError(
        'GetNetEnergies is not available for namespaces: '
        '${candidateRpcNamespaces.join(', ')}',
      );
    }

    throw StateError('No RPC namespace configured for GetNetEnergies.');
  }

  List<String> _resolveNetEnergiesNamespaces({String? preferredRpcNamespace}) {
    final namespaces = <String>[];
    final seen = <String>{};

    void addNamespace(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return;
      }
      final normalized = _toRpcNamespace(trimmed);
      final key = normalized.toLowerCase();
      if (seen.contains(key)) {
        return;
      }
      seen.add(key);
      namespaces.add(normalized);
    }

    if (preferredRpcNamespace != null) {
      addNamespace(preferredRpcNamespace);
    }

    addNamespace('Switch');
    addNamespace('EMData');
    addNamespace('EM1Data');

    return namespaces;
  }

  bool _isNoHandlerError(Object error, String method) {
    if (error is! ShellyApiException) {
      return false;
    }

    final message = error.message.toLowerCase();
    final methodLower = method.toLowerCase();
    return error.code == 404 &&
        message.contains('no handler') &&
        message.contains(methodLower);
  }

  String _toRpcNamespace(String value) {
    return switch (value.toLowerCase()) {
      'switch' => 'Switch',
      'emdata' => 'EMData',
      'em1data' => 'EM1Data',
      _ => value,
    };
  }

  String _randomHex(int length) {
    const chars = '0123456789abcdef';
    final buffer = StringBuffer();
    for (var index = 0; index < length; index += 1) {
      buffer.write(chars[_random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  Uri _rpcUri() {
    return Uri(
      scheme: useHttps ? 'https' : 'http',
      host: host,
      port: port,
      path: '/rpc',
    );
  }

  Map<String, String> get _defaultHeaders {
    return const {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
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
}

class ShellyApiResponse {
  const ShellyApiResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

class ShellyEnergyComponent {
  const ShellyEnergyComponent({required this.rpcNamespace, required this.id});

  final String rpcNamespace;
  final int id;
}

class _ShellyNetEnergiesResult {
  const _ShellyNetEnergiesResult({
    required this.data,
    required this.rpcNamespace,
  });

  final ShellyEnergyData data;
  final String rpcNamespace;
}
