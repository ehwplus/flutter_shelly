import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_shelly/flutter_shelly.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});

  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _hostController = TextEditingController(text: '192.168.178.50');
  final _portController = TextEditingController(text: '80');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  HttpShellyApiClient? _client;
  ShellyDeviceInfo? _deviceInfo;
  Map<String, dynamic>? _status;
  ShellyEnergyUsage? _energyUsage;
  ShellyEnergyData? _energyData;
  List<int> _availableSwitchIds = const [0, 1, 2, 3];

  bool _useHttps = false;
  bool _isLoading = false;
  String? _error;

  ShellyEnergyPeriod _selectedPeriod = ShellyEnergyPeriod.hourly;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 1));
  DateTime _endDate = DateTime.now();
  int _selectedSwitchId = 0;

  bool get _isConnected => _client != null;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _client?.close();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }

    setState(() {
      _hostController.text =
          prefs.getString('shelly_host') ?? _hostController.text;
      _portController.text =
          prefs.getString('shelly_port') ?? _portController.text;
      _usernameController.text = prefs.getString('shelly_username') ?? '';
      _passwordController.text = prefs.getString('shelly_password') ?? '';
      _selectedSwitchId = _normalizeSwitchId(
        int.tryParse(prefs.getString('shelly_switch_id') ?? '0') ?? 0,
      );
      _useHttps = prefs.getBool('shelly_https') ?? false;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shelly_host', _hostController.text.trim());
    await prefs.setString('shelly_port', _portController.text.trim());
    await prefs.setString('shelly_username', _usernameController.text.trim());
    await prefs.setString('shelly_password', _passwordController.text);
    await prefs.setString('shelly_switch_id', _selectedSwitchId.toString());
    await prefs.setBool('shelly_https', _useHttps);
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await action();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();

    await _runBusy(() async {
      final settings = _resolveConnectionSettings();
      final username = _usernameController.text.trim();
      final password = _passwordController.text;

      HttpShellyApiClient? createdClient;
      try {
        createdClient = HttpShellyApiClient(
          host: settings.host,
          port: settings.port,
          useHttps: settings.useHttps,
          username: username.isEmpty ? null : username,
          password: password.isEmpty ? null : password,
        );

        final deviceInfo = await createdClient.getDeviceInfo();
        final status = await createdClient.getStatus();
        final availableSwitchIds = _extractSwitchIds(status);
        final selectedSwitchId = _normalizeSwitchIdForList(
          _selectedSwitchId,
          availableSwitchIds,
        );
        final usage = await createdClient.getEnergyUsage(id: selectedSwitchId);

        await _savePrefs();

        if (!mounted) {
          createdClient.close();
          return;
        }

        final oldClient = _client;
        setState(() {
          _client = createdClient;
          _deviceInfo = deviceInfo;
          _status = status;
          _availableSwitchIds = availableSwitchIds;
          _selectedSwitchId = selectedSwitchId;
          _energyUsage = usage;
          _energyData = null;
        });
        oldClient?.close();
      } catch (_) {
        createdClient?.close();
        rethrow;
      }
    });
  }

  Future<void> _refreshStatus() async {
    await _runBusy(() async {
      final client = _requireClient();
      final status = await client.getStatus();
      final availableSwitchIds = _extractSwitchIds(status);
      final selectedSwitchId = _normalizeSwitchIdForList(
        _selectedSwitchId,
        availableSwitchIds,
      );
      final usage = await client.getEnergyUsage(id: selectedSwitchId);

      if (!mounted) {
        return;
      }

      setState(() {
        _status = status;
        _availableSwitchIds = availableSwitchIds;
        _selectedSwitchId = selectedSwitchId;
        _energyUsage = usage;
      });
    });
  }

  Future<void> _setSwitchState(bool on) async {
    await _runBusy(() async {
      final client = _requireClient();
      await client.setSwitchState(on, id: _switchId);
      final status = await client.getStatus();
      final availableSwitchIds = _extractSwitchIds(status);
      final selectedSwitchId = _normalizeSwitchIdForList(
        _selectedSwitchId,
        availableSwitchIds,
      );
      final usage = await client.getEnergyUsage(id: selectedSwitchId);

      if (!mounted) {
        return;
      }

      setState(() {
        _status = status;
        _energyUsage = usage;
        _availableSwitchIds = availableSwitchIds;
        _selectedSwitchId = selectedSwitchId;
      });
    });
  }

  Future<void> _onSwitchIdChanged(int switchId) async {
    final normalized = _normalizeSwitchId(switchId);
    if (normalized == _selectedSwitchId) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedSwitchId = normalized;
      _energyData = null;
    });
    await _savePrefs();
    if (_isConnected) {
      await _loadEnergyUsage();
    }
  }

  Future<void> _loadEnergyUsage() async {
    await _runBusy(() async {
      final client = _requireClient();
      final usage = await client.getEnergyUsage(id: _switchId);
      final rangeData = _loadRangeConsumptionData(usage);

      if (!mounted) {
        return;
      }
      setState(() {
        _energyUsage = usage;
        _energyData = rangeData;
      });
    });
  }

  ShellyEnergyData _loadRangeConsumptionData(ShellyEnergyUsage usage) {
    final minutePoints = usage.byMinuteMilliWattHours;
    final selectedPeriod = _selectedPeriod;
    final periodSeconds = selectedPeriod.seconds;
    final rangeStartTs = _normalizedStartDate.millisecondsSinceEpoch ~/ 1000;
    final rangeEndTs = _normalizedEndDate.millisecondsSinceEpoch ~/ 1000;
    final intervalType = _toIntervalType(selectedPeriod);

    if (minutePoints.isEmpty || usage.minuteTimestamp <= 0) {
      return ShellyEnergyData(
        intervalType: intervalType,
        period: selectedPeriod,
        metricKey: 'aenergy.by_minute',
        points: const [],
        availableKeys: const ['aenergy.by_minute'],
      );
    }

    final byBucketTs = <int, double>{};
    final currentMinuteStartTs = usage.minuteTimestamp;
    for (var index = 0; index < minutePoints.length; index += 1) {
      final minuteStartTs =
          currentMinuteStartTs - ((minutePoints.length - index) * 60);
      if (minuteStartTs < rangeStartTs || minuteStartTs > rangeEndTs) {
        continue;
      }
      final bucketTs = (minuteStartTs ~/ periodSeconds) * periodSeconds;
      byBucketTs[bucketTs] =
          (byBucketTs[bucketTs] ?? 0) + (minutePoints[index] / 1000);
    }

    final sortedTs = byBucketTs.keys.toList(growable: false)..sort();
    final points = sortedTs
        .map(
          (ts) => ShellyEnergyDataPoint(
            start: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
            energyWh: byBucketTs[ts] ?? 0,
          ),
        )
        .toList(growable: false);

    return ShellyEnergyData(
      intervalType: intervalType,
      period: selectedPeriod,
      metricKey: 'aenergy.by_minute',
      points: points,
      availableKeys: const ['aenergy.by_minute'],
    );
  }

  ShellyEnergyDataIntervalType _toIntervalType(ShellyEnergyPeriod period) {
    return switch (period) {
      ShellyEnergyPeriod.fiveMinutes =>
        ShellyEnergyDataIntervalType.fiveMinutes,
      ShellyEnergyPeriod.fifteenMinutes =>
        ShellyEnergyDataIntervalType.fifteenMinutes,
      ShellyEnergyPeriod.thirtyMinutes =>
        ShellyEnergyDataIntervalType.thirtyMinutes,
      ShellyEnergyPeriod.hourly => ShellyEnergyDataIntervalType.hourly,
    };
  }

  List<int> _extractSwitchIds(Map<String, dynamic> status) {
    final ids = <int>{};
    for (final key in status.keys) {
      final match = RegExp(r'^switch:(\d+)$').firstMatch(key);
      final parsed = int.tryParse(match?.group(1) ?? '');
      if (parsed != null) {
        ids.add(parsed);
      }
    }

    if (ids.isEmpty) {
      return const [0, 1, 2, 3];
    }
    final sorted = ids.toList(growable: false)..sort();
    return sorted;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initialDate = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: initialDate,
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _startDate = _endDate;
        }
      }
    });
  }

  _ConnectionSettings _resolveConnectionSettings() {
    final rawHost = _hostController.text.trim();
    if (rawHost.isEmpty) {
      throw const FormatException('Bitte Host oder URL eingeben.');
    }

    if (rawHost.contains('://')) {
      final uri = Uri.tryParse(rawHost);
      if (uri == null || uri.host.isEmpty) {
        throw const FormatException(
          'Ungueltige URL. Bitte z.B. http://192.168.178.50 verwenden.',
        );
      }
      final useHttps = uri.scheme.toLowerCase() == 'https';
      final port = uri.hasPort ? uri.port : (useHttps ? 443 : 80);
      return _ConnectionSettings(
        host: uri.host,
        port: port,
        useHttps: useHttps,
      );
    }

    final parsedPort = int.tryParse(_portController.text.trim());
    final resolvedPort = parsedPort ?? (_useHttps ? 443 : 80);
    return _ConnectionSettings(
      host: rawHost,
      port: resolvedPort,
      useHttps: _useHttps,
    );
  }

  HttpShellyApiClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('Bitte zuerst verbinden.');
    }
    return client;
  }

  int get _switchId => _selectedSwitchId;

  int _normalizeSwitchId(int value) {
    return _normalizeSwitchIdForList(value, _availableSwitchIds);
  }

  int _normalizeSwitchIdForList(int value, List<int> switchIds) {
    if (switchIds.isEmpty) {
      return 0;
    }
    if (switchIds.contains(value)) {
      return value;
    }
    return switchIds.first;
  }

  DateTime get _normalizedStartDate {
    return DateTime(_startDate.year, _startDate.month, _startDate.day);
  }

  DateTime get _normalizedEndDate {
    return DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLoading) const LinearProgressIndicator(),
              _buildConnectionCard(),
              const SizedBox(height: 12),
              _buildEnergyControlCard(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              if (_deviceInfo != null) ...[
                const SizedBox(height: 12),
                _buildDeviceInfoCard(_deviceInfo!),
              ],
              if (_status != null) ...[
                const SizedBox(height: 12),
                _buildStatusCard(_status!),
              ],
              if (_energyUsage != null) ...[
                const SizedBox(height: 12),
                _buildEnergyUsageCard(_energyUsage!),
              ],
              if (_energyData != null) ...[
                const SizedBox(height: 12),
                _buildEnergyDataCard(_energyData!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verbindung',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Hinweis: 192.168.x.x funktioniert nur im lokalen Netz. '
              'Fuer externen Zugriff HTTPS mit oeffentlicher Adresse oder VPN verwenden.',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Host oder URL',
                hintText: '192.168.178.50 oder http://192.168.178.50',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Port'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SwitchListTile(
                    value: _useHttps,
                    title: const Text('HTTPS'),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (value) {
                      setState(() {
                        _useHttps = value;
                        _portController.text = value ? '443' : '80';
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username (optional)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Passwort (optional)',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _connect,
                  child: const Text('Verbinden'),
                ),
                OutlinedButton(
                  onPressed: _isConnected ? _refreshStatus : null,
                  child: const Text('Status aktualisieren'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnergyControlCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Energie-Abfrage',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: ValueKey<int>(_selectedSwitchId),
              initialValue: _selectedSwitchId,
              decoration: const InputDecoration(
                labelText: 'Steckplatz (Switch ID)',
              ),
              items: _availableSwitchIds
                  .map(
                    (id) =>
                        DropdownMenuItem(value: id, child: Text('Slot $id')),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                _onSwitchIdChanged(value);
              },
            ),
            const SizedBox(height: 8),
            // Erweiterte RPC-Felder sind hier bewusst ausgeblendet.
            // Fuer PlusPlugS/PowerStrip nutzen wir direkt `switch:<id>.aenergy`.
            DropdownButtonFormField<ShellyEnergyPeriod>(
              initialValue: _selectedPeriod,
              decoration: const InputDecoration(labelText: 'Periode'),
              items: ShellyEnergyPeriod.values
                  .map(
                    (period) => DropdownMenuItem(
                      value: period,
                      child: Text(_periodLabel(period)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (period) {
                if (period == null) {
                  return;
                }
                setState(() {
                  _selectedPeriod = period;
                });
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(isStart: true),
                    icon: const Icon(Icons.calendar_today),
                    label: Text('Start: ${_formatDate(_startDate)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(isStart: false),
                    icon: const Icon(Icons.calendar_today),
                    label: Text('Ende: ${_formatDate(_endDate)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Hinweis: PlusPlugS/PowerStrip liefern lokal nur '
              '`aenergy.by_minute` (kurzer Verlauf) und `aenergy.total` '
              '(Zaehlerstand). Tag/Woche/Monat entsteht durch fortlaufendes '
              'Speichern von `aenergy.total`.',
              style: TextStyle(color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _isConnected ? () => _setSwitchState(true) : null,
                  child: const Text('Switch ON'),
                ),
                OutlinedButton(
                  onPressed: _isConnected ? () => _setSwitchState(false) : null,
                  child: const Text('Switch OFF'),
                ),
                FilledButton(
                  onPressed: _isConnected ? _loadEnergyUsage : null,
                  child: const Text('Verbrauch laden'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfoCard(ShellyDeviceInfo info) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Device Info',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _valueRow('Model', info.model),
            _valueRow('App', info.app),
            _valueRow('Version', info.version),
            _valueRow('MAC', info.mac),
            _valueRow('Generation', info.generation.toString()),
            _valueRow('Auth aktiviert', info.authEnabled ? 'ja' : 'nein'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(Map<String, dynamic> status) {
    final selectedSwitchStatus = _asMap(status['switch:$_switchId']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Status', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _valueRow('Komponenten', status.length.toString()),
            if (selectedSwitchStatus.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('switch:<id> Snapshot'),
              const SizedBox(height: 4),
              SelectableText(
                _prettyJson(selectedSwitchStatus),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEnergyUsageCard(ShellyEnergyUsage usage) {
    final byMinutePoints = _buildByMinutePoints(usage);
    final seriesEntries = usage.activeEnergySeries.entries.toList(
      growable: false,
    )..sort((a, b) => a.key.compareTo(b.key));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aktueller Verbrauch',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _valueRow('Switch ID', usage.id.toString()),
            _valueRow('Output', usage.output ? 'on' : 'off'),
            _valueRow('Power', '${_fmtDouble(usage.activePowerW)} W'),
            _valueRow(
              'Total active energy',
              '${_fmtDouble(usage.totalActiveEnergyWh)} Wh',
            ),
            _valueRow(
              'Total returned energy',
              usage.totalReturnedEnergyWh == null
                  ? '-'
                  : '${_fmtDouble(usage.totalReturnedEnergyWh)} Wh',
            ),
            _valueRow(
              'Voltage',
              usage.voltageV == null ? '-' : '${_fmtDouble(usage.voltageV)} V',
            ),
            _valueRow(
              'Current',
              usage.currentA == null ? '-' : '${_fmtDouble(usage.currentA)} A',
            ),
            _valueRow(
              'PF',
              usage.powerFactor == null ? '-' : _fmtDouble(usage.powerFactor),
            ),
            _valueRow(
              'Freq',
              usage.frequencyHz == null
                  ? '-'
                  : '${_fmtDouble(usage.frequencyHz)} Hz',
            ),
            _valueRow(
              'aenergy.minute_ts',
              _formatUnixSecondTimestamp(usage.minuteTimestamp),
            ),
            if (seriesEntries.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Verfuegbare aenergy-Zeitbereiche',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              for (final entry in seriesEntries)
                _valueRow(entry.key, _formatEnergySeriesValues(entry.value)),
            ],
            if (byMinutePoints.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'aenergy.by_minute (letzte vollen Minuten)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              for (final point in byMinutePoints)
                Text(
                  '${_formatDateTime(point.start)}-${_formatDateTime(point.end)}: '
                  '${_fmtDouble(point.energyMilliWh, fractionDigits: 0)} mWh '
                  '(${_fmtDouble(point.energyWh, fractionDigits: 3)} Wh)',
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEnergyDataCard(ShellyEnergyData data) {
    final totalEnergy = data.points.fold<double>(
      0,
      (sum, point) => sum + point.energyWh,
    );
    final preview = data.points.take(20).toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verbrauch Verlauf',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _valueRow('Metric key', data.metricKey),
            if (data.metricKey == 'aenergy.by_minute')
              const Text(
                'Hinweis: Diese Geraete liefern den Verlauf direkt ueber '
                '`switch:<id>.aenergy.by_minute` (letzte vollen Minuten).',
                style: TextStyle(color: Colors.orange),
              ),
            _valueRow('Points', data.points.length.toString()),
            _valueRow('Total', '${_fmtDouble(totalEnergy)} Wh'),
            _valueRow('Period', _periodLabel(data.period)),
            _valueRow(
              'Range',
              '${_formatDate(_startDate)} bis ${_formatDate(_endDate)}',
            ),
            if (data.availableKeys.isNotEmpty)
              _valueRow('Available keys', data.availableKeys.join(', ')),
            const SizedBox(height: 8),
            const Text('Vorschau (max. 20 Punkte):'),
            const SizedBox(height: 4),
            for (final point in preview)
              Text(
                '${_formatDateTime(point.start)} -> ${_fmtDouble(point.energyWh)} Wh',
              ),
            if (data.points.length > preview.length)
              Text('... ${data.points.length - preview.length} weitere Punkte'),
          ],
        ),
      ),
    );
  }

  Widget _valueRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              '$key:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  String _prettyJson(Map<String, dynamic> map) {
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  String _periodLabel(ShellyEnergyPeriod period) {
    return switch (period) {
      ShellyEnergyPeriod.fiveMinutes => '300s (5min)',
      ShellyEnergyPeriod.fifteenMinutes => '900s (15min)',
      ShellyEnergyPeriod.thirtyMinutes => '1800s (30min)',
      ShellyEnergyPeriod.hourly => '3600s (1h)',
    };
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _formatDateTime(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.year}-$month-$day $hour:$minute';
  }

  String _fmtDouble(double? value, {int fractionDigits = 2}) {
    if (value == null) {
      return '-';
    }
    return value.toStringAsFixed(fractionDigits);
  }

  String _formatEnergySeriesValues(List<double> values) {
    if (values.isEmpty) {
      return '-';
    }

    const previewCount = 8;
    final preview = values.length <= previewCount
        ? values
        : values.sublist(values.length - previewCount);
    final summary = preview.map((value) => _fmtDouble(value)).join(', ');
    if (values.length > preview.length) {
      return '$summary ... (${values.length} Werte)';
    }
    return '$summary (${values.length} Werte)';
  }

  String _formatUnixSecondTimestamp(int timestamp) {
    if (timestamp <= 0) {
      return '-';
    }

    final utc = DateTime.fromMillisecondsSinceEpoch(
      timestamp * 1000,
      isUtc: true,
    );
    return '${_formatDateTime(utc)} UTC / ${_formatDateTime(utc.toLocal())} lokal';
  }

  List<_ByMinutePoint> _buildByMinutePoints(ShellyEnergyUsage usage) {
    final values = usage.byMinuteMilliWattHours;
    if (usage.minuteTimestamp <= 0 || values.isEmpty) {
      return const [];
    }

    final currentMinuteStartUtc = DateTime.fromMillisecondsSinceEpoch(
      usage.minuteTimestamp * 1000,
      isUtc: true,
    );
    final points = <_ByMinutePoint>[];
    for (var index = 0; index < values.length; index += 1) {
      final startUtc = currentMinuteStartUtc.subtract(
        Duration(minutes: values.length - index),
      );
      final endUtc = startUtc.add(const Duration(minutes: 1));
      final energyMilliWh = values[index];
      points.add(
        _ByMinutePoint(
          start: startUtc.toLocal(),
          end: endUtc.toLocal(),
          energyMilliWh: energyMilliWh,
          energyWh: energyMilliWh / 1000,
        ),
      );
    }
    return points;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }
}

class _ConnectionSettings {
  const _ConnectionSettings({
    required this.host,
    required this.port,
    required this.useHttps,
  });

  final String host;
  final int port;
  final bool useHttps;
}

class _ByMinutePoint {
  const _ByMinutePoint({
    required this.start,
    required this.end,
    required this.energyMilliWh,
    required this.energyWh,
  });

  final DateTime start;
  final DateTime end;
  final double energyMilliWh;
  final double energyWh;
}
