class ShellyApiException implements Exception {
  const ShellyApiException(
    this.code,
    this.message, {
    this.payload,
    this.httpStatusCode,
  });

  final int code;
  final String message;
  final Map<String, dynamic>? payload;
  final int? httpStatusCode;

  @override
  String toString() {
    return 'ShellyApiException(code: $code, message: $message, httpStatusCode: $httpStatusCode)';
  }
}

class ShellyProtocolException implements Exception {
  const ShellyProtocolException(this.message);

  final String message;

  @override
  String toString() => 'ShellyProtocolException(message: $message)';
}

class ShellyAuthenticationException implements Exception {
  const ShellyAuthenticationException(this.message);

  final String message;

  @override
  String toString() => 'ShellyAuthenticationException(message: $message)';
}
