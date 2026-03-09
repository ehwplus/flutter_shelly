class ShellyDeviceInfo {
  const ShellyDeviceInfo({
    required this.id,
    required this.model,
    required this.mac,
    required this.app,
    required this.version,
    required this.generation,
    required this.authEnabled,
    this.name,
    this.slot,
    this.key,
    this.batch,
    this.fwId,
    this.profile,
  });

  factory ShellyDeviceInfo.fromJson(Map<String, dynamic> json) {
    return ShellyDeviceInfo(
      id: json['id']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      mac: json['mac']?.toString() ?? '',
      app: json['app']?.toString() ?? '',
      version: json['ver']?.toString() ?? '',
      generation: _parseInt(json['gen']) ?? 0,
      authEnabled: json['auth_en'] == true,
      name: json['name']?.toString(),
      slot: _parseInt(json['slot']),
      key: json['key']?.toString(),
      batch: json['batch']?.toString(),
      fwId: json['fw_id']?.toString(),
      profile: json['profile']?.toString(),
    );
  }

  final String id;
  final String model;
  final String mac;
  final String app;
  final String version;
  final int generation;
  final bool authEnabled;
  final String? name;
  final int? slot;
  final String? key;
  final String? batch;
  final String? fwId;
  final String? profile;

  static int? _parseInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
