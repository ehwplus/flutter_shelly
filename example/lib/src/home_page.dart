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
  final _switchIdController = TextEditingController(text: '0');
  final _componentIdController = TextEditingController(text: '0');
  final _rpcNamespaceController = TextEditingController(text: 'EMData');
  final _metricKeyController = TextEditingController();

  HttpShellyApiClient? _client;
  ShellyDeviceInfo? _deviceInfo;
  Map<String, dynamic>? _status;
  ShellyEnergyUsage? _energyUsage;
  ShellyEnergyData? _energyData;
  Map<ShellyEnergyPeriod, ShellyEnergyData> _allPeriodsData = const {};
  List<ShellyEnergyActivity> _activities = const [];
  List<ShellyEnergyComponent> _energyComponents = const [];

  bool _useHttps = false;
  bool _isLoading = false;
  String? _error;

  ShellyEnergyPeriod _selectedPeriod = ShellyEnergyPeriod.hourly;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 1));
  DateTime _endDate = DateTime.now();

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
    _switchIdController.dispose();
    _componentIdController.dispose();
    _rpcNamespaceController.dispose();
    _metricKeyController.dispose();
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
      _switchIdController.text =
          prefs.getString('shelly_switch_id') ?? _switchIdController.text;
      _componentIdController.text =
          prefs.getString('shelly_component_id') ?? _componentIdController.text;
      _rpcNamespaceController.text =
          prefs.getString('shelly_rpc_namespace') ??
          _rpcNamespaceController.text;
      _metricKeyController.text = prefs.getString('shelly_metric_key') ?? '';
      _useHttps = prefs.getBool('shelly_https') ?? false;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shelly_host', _hostController.text.trim());
    await prefs.setString('shelly_port', _portController.text.trim());
    await prefs.setString('shelly_username', _usernameController.text.trim());
    await prefs.setString('shelly_password', _passwordController.text);
    await prefs.setString('shelly_switch_id', _switchIdController.text.trim());
    await prefs.setString(
      'shelly_component_id',
      _componentIdController.text.trim(),
    );
    await prefs.setString(
      'shelly_rpc_namespace',
      _rpcNamespaceController.text.trim(),
    );
    await prefs.setString(
      'shelly_metric_key',
      _metricKeyController.text.trim(),
    );
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
        final components = await createdClient.getEnergyComponents();
        final usage = await createdClient.getEnergyUsage(id: _switchId);

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
          _energyComponents = components;
          _energyUsage = usage;
          _energyData = null;
          _allPeriodsData = const {};
          _activities = const [];
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
      final components = await client.getEnergyComponents();
      final usage = await client.getEnergyUsage(id: _switchId);

      if (!mounted) {
        return;
      }

      setState(() {
        _status = status;
        _energyComponents = components;
        _energyUsage = usage;
      });
    });
  }

  Future<void> _setSwitchState(bool on) async {
    await _runBusy(() async {
      final client = _requireClient();
      await client.setSwitchState(on, id: _switchId);
      final status = await client.getStatus();
      final usage = await client.getEnergyUsage(id: _switchId);

      if (!mounted) {
        return;
      }

      setState(() {
        _status = status;
        _energyUsage = usage;
      });
    });
  }

  Future<void> _loadEnergyUsage() async {
    await _runBusy(() async {
      final client = _requireClient();
      final usage = await client.getEnergyUsage(id: _switchId);

      if (!mounted) {
        return;
      }
      setState(() {
        _energyUsage = usage;
      });
    });
  }

  Future<void> _loadEnergyData() async {
    await _runBusy(() async {
      final client = _requireClient();
      final interval = _createInterval(activityMode: false);
      final data = await client.getEnergyData(interval);

      if (!mounted) {
        return;
      }
      setState(() {
        _energyData = data;
        _activities = const [];
      });
    });
  }

  Future<void> _loadActivities() async {
    await _runBusy(() async {
      final client = _requireClient();
      final interval = _createInterval(activityMode: true);
      final data = await client.getEnergyData(interval);
      final activities = data.activities();

      if (!mounted) {
        return;
      }
      setState(() {
        _energyData = data;
        _activities = activities;
      });
    });
  }

  Future<void> _loadAllPeriods() async {
    await _runBusy(() async {
      final client = _requireClient();
      final metricKey = _metricKeyController.text.trim();
      final allData = await client.getEnergyDataForAllPeriods(
        startDate: _normalizedStartDate,
        endDate: _normalizedEndDate,
        componentId: _componentId,
        rpcNamespace: _rpcNamespace,
        metricKey: metricKey.isEmpty ? null : metricKey,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _allPeriodsData = allData;
      });
    });
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

  ShellyEnergyDataInterval _createInterval({required bool activityMode}) {
    final metricKey = _metricKeyController.text.trim();
    final metric = metricKey.isEmpty ? null : metricKey;

    if (activityMode) {
      return ShellyEnergyDataInterval.activity(
        startDate: _normalizedStartDate,
        endDate: _normalizedEndDate,
        period: _selectedPeriod,
        componentId: _componentId,
        rpcNamespace: _rpcNamespace,
        metricKey: metric,
      );
    }

    return switch (_selectedPeriod) {
      ShellyEnergyPeriod.fiveMinutes => ShellyEnergyDataInterval.fiveMinutes(
        startDate: _normalizedStartDate,
        endDate: _normalizedEndDate,
        componentId: _componentId,
        rpcNamespace: _rpcNamespace,
        metricKey: metric,
      ),
      ShellyEnergyPeriod.fifteenMinutes =>
        ShellyEnergyDataInterval.fifteenMinutes(
          startDate: _normalizedStartDate,
          endDate: _normalizedEndDate,
          componentId: _componentId,
          rpcNamespace: _rpcNamespace,
          metricKey: metric,
        ),
      ShellyEnergyPeriod.thirtyMinutes =>
        ShellyEnergyDataInterval.thirtyMinutes(
          startDate: _normalizedStartDate,
          endDate: _normalizedEndDate,
          componentId: _componentId,
          rpcNamespace: _rpcNamespace,
          metricKey: metric,
        ),
      ShellyEnergyPeriod.hourly => ShellyEnergyDataInterval.hourly(
        startDate: _normalizedStartDate,
        endDate: _normalizedEndDate,
        componentId: _componentId,
        rpcNamespace: _rpcNamespace,
        metricKey: metric,
      ),
    };
  }

  HttpShellyApiClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('Bitte zuerst verbinden.');
    }
    return client;
  }

  int get _switchId => int.tryParse(_switchIdController.text.trim()) ?? 0;

  int get _componentId => int.tryParse(_componentIdController.text.trim()) ?? 0;

  String get _rpcNamespace {
    final namespace = _rpcNamespaceController.text.trim();
    return namespace.isEmpty ? 'EMData' : namespace;
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
              if (_energyComponents.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildEnergyComponentsCard(),
              ],
              if (_energyUsage != null) ...[
                const SizedBox(height: 12),
                _buildEnergyUsageCard(_energyUsage!),
              ],
              if (_energyData != null) ...[
                const SizedBox(height: 12),
                _buildEnergyDataCard(_energyData!),
              ],
              if (_activities.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildActivitiesCard(_activities),
              ],
              if (_allPeriodsData.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildAllPeriodsCard(_allPeriodsData),
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _switchIdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Switch ID'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _componentIdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Component ID',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _rpcNamespaceController,
              decoration: const InputDecoration(
                labelText: 'RPC Namespace',
                hintText: 'EMData oder EM1Data',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _metricKeyController,
              decoration: const InputDecoration(
                labelText: 'Metric Key (optional)',
                hintText: 'z.B. total_act_energy',
              ),
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _isConnected ? _loadEnergyUsage : null,
                  child: const Text('Verbrauch laden'),
                ),
                FilledButton.tonal(
                  onPressed: _isConnected ? _loadEnergyData : null,
                  child: const Text('Zeitreihe laden'),
                ),
                FilledButton.tonal(
                  onPressed: _isConnected ? _loadActivities : null,
                  child: const Text('Aktivitaeten auswerten'),
                ),
                OutlinedButton(
                  onPressed: _isConnected ? _loadAllPeriods : null,
                  child: const Text('Alle Perioden laden'),
                ),
              ],
            ),
            const SizedBox(height: 8),
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

  Widget _buildEnergyComponentsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gefundene Energy Components',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final component in _energyComponents)
              Text('- ${component.rpcNamespace} (id: ${component.id})'),
          ],
        ),
      ),
    );
  }

  Widget _buildEnergyUsageCard(ShellyEnergyUsage usage) {
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
            _valueRow('Minute TS', usage.minuteTimestamp.toString()),
            if (usage.byMinuteWh.isNotEmpty)
              _valueRow(
                'by_minute',
                usage.byMinuteWh.map((value) => _fmtDouble(value)).join(', '),
              ),
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
              'Energy Data',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _valueRow('Metric key', data.metricKey),
            _valueRow('Points', data.points.length.toString()),
            _valueRow('Total', '${_fmtDouble(totalEnergy)} Wh'),
            _valueRow('Period', _periodLabel(data.period)),
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

  Widget _buildActivitiesCard(List<ShellyEnergyActivity> activities) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aktivitaeten',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final activity in activities)
              Text(
                '${_formatDateTime(activity.start)} -> ${_formatDateTime(activity.end)} '
                '(${_fmtDouble(activity.energyWh)} Wh)',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllPeriodsCard(
    Map<ShellyEnergyPeriod, ShellyEnergyData> byPeriod,
  ) {
    final entries = byPeriod.entries.toList(growable: false)
      ..sort((a, b) => a.key.seconds.compareTo(b.key.seconds));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Alle verfuegbaren Perioden',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final entry in entries)
              _valueRow(
                _periodLabel(entry.key),
                '${entry.value.points.length} Punkte, '
                '${_fmtDouble(entry.value.points.fold<double>(0, (sum, point) => sum + point.energyWh))} Wh',
              ),
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
