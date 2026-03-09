import 'package:http/http.dart' as http;

import 'shelly_api_client.dart';

class HttpShellyApiClient extends ShellyApiClient {
  HttpShellyApiClient({
    required super.host,
    super.port = 80,
    super.useHttps = false,
    super.username,
    super.password,
    super.requestSource = 'flutter_shelly',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<ShellyApiResponse> post(
    Uri url, {
    Map<String, String>? headers,
    required String body,
  }) async {
    final response = await _client.post(url, headers: headers, body: body);

    return ShellyApiResponse(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers,
    );
  }

  void close() {
    _client.close();
  }
}
