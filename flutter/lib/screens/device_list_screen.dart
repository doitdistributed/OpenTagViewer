import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../models/beacon_information.dart';
import '../models/beacon_location_report.dart';
import '../services/beacon_import_service.dart';
import '../state/app_state.dart';
import 'device_info_screen.dart';
import 'map_screen.dart';
import 'settings_screen.dart';

/// Shows the list of imported beacons and lets users import new ones.
class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().refreshReports();
    });
  }

  Future<void> _importZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.single.bytes == null) return;

    setState(() => _importing = true);
    try {
      final service = BeaconImportService();
      final importData =
          service.extractZip(result.files.single.bytes!);
      final beacons = service.parseBeacons(importData);

      if (!mounted) return;
      final appState = context.read<AppState>();
      appState.setBeacons(beacons);
      await appState.refreshReports();
    } on ZipImporterException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to import: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _openMaps() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MapScreen()),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final beacons = appState.beacons;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Devices'),
        actions: [
          if (beacons.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.map_outlined),
              tooltip: 'Map view',
              onPressed: _openMaps,
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _buildBody(appState, beacons),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _importZip,
        icon: _importing
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.file_upload_outlined),
        label: const Text('Import Export Zip'),
      ),
    );
  }

  Widget _buildBody(AppState appState, List<BeaconInformation> beacons) {
    if (beacons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off_outlined,
                  size: 72,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              const Text(
                'No devices imported yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Import the .zip export file created by the OpenTagViewer macOS app to start tracking your AirTags.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => appState.refreshReports(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: beacons.length,
        itemBuilder: (context, index) {
          final beacon = beacons[index];
          final latestReport = appState.latestReportFor(beacon.beaconId);
          return _BeaconListTile(
            beacon: beacon,
            latestReport: latestReport,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DeviceInfoScreen(beacon: beacon),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BeaconListTile extends StatelessWidget {
  final BeaconInformation beacon;
  final BeaconLocationReport? latestReport;
  final VoidCallback onTap;

  const _BeaconListTile({
    required this.beacon,
    required this.latestReport,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLocation = latestReport != null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: beacon.isEmojiFilled
              ? Text(beacon.emoji!, style: const TextStyle(fontSize: 22))
              : Icon(
                  beacon.isAirTag
                      ? Icons.location_on
                      : Icons.devices_other,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
        ),
        title: Text(beacon.name ?? beacon.beaconId,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: hasLocation
            ? Text(
                '${latestReport!.latitude.toStringAsFixed(5)}, '
                '${latestReport!.longitude.toStringAsFixed(5)}\n'
                '${_formatDate(latestReport!.dateTime)}',
              )
            : const Text('No location data yet'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        isThreeLine: hasLocation,
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
