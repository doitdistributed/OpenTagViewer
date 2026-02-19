import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/beacon_information.dart';
import '../state/app_state.dart';
import 'history_screen.dart';
import 'map_screen.dart';

/// Shows detailed information about a single beacon and lets the user
/// customise its name / emoji, or remove it.
///
/// Mirrors [DeviceInfoActivity] from the Android app.
class DeviceInfoScreen extends StatefulWidget {
  final BeaconInformation beacon;

  const DeviceInfoScreen({super.key, required this.beacon});

  @override
  State<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends State<DeviceInfoScreen> {
  late TextEditingController _nameController;
  late TextEditingController _emojiController;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.beacon.userOverrideName ?? '');
    _emojiController =
        TextEditingController(text: widget.beacon.userOverrideEmoji ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  void _saveOverrides() {
    final appState = context.read<AppState>();
    appState.updateBeaconOverrides(
      widget.beacon.beaconId,
      name: _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : null,
      emoji: _emojiController.text.trim().isNotEmpty
          ? _emojiController.text.trim()
          : null,
    );
    setState(() => _editing = false);
  }

  Future<void> _confirmRemove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Device'),
        content: Text(
            'Remove ${widget.beacon.name ?? widget.beacon.beaconId} from the list? '
            'This only removes it from the app — the device is not affected.'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          FilledButton(
            child: const Text('Remove'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context.read<AppState>().removeBeacon(widget.beacon.beaconId);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final beacon = widget.beacon;
    final appState = context.watch<AppState>();
    final latestReport = appState.latestReportFor(beacon.beaconId);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(beacon.name ?? beacon.beaconId),
        actions: [
          if (!_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit name/emoji',
              onPressed: () => setState(() => _editing = true),
            ),
          if (_editing) ...[
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Save',
              onPressed: _saveOverrides,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onPressed: () => setState(() => _editing = false),
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: beacon.isEmojiFilled
                        ? Text(beacon.emoji!,
                            style: const TextStyle(fontSize: 32))
                        : Icon(
                            Icons.location_on,
                            size: 36,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          beacon.name ?? beacon.beaconId,
                          style: theme.textTheme.titleLarge,
                        ),
                        if (beacon.isAirTag)
                          Chip(
                            label: const Text('AirTag'),
                            labelStyle:
                                TextStyle(color: theme.colorScheme.primary),
                            backgroundColor:
                                theme.colorScheme.primaryContainer,
                            visualDensity: VisualDensity.compact,
                          ),
                        if (beacon.isIpad)
                          const Chip(label: Text('iPad')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_editing) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Customise',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Display Name (optional)',
                        border: OutlineInputBorder(),
                        helperText:
                            'Leave empty to use the original name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emojiController,
                      decoration: const InputDecoration(
                        labelText: 'Emoji (optional)',
                        border: OutlineInputBorder(),
                        helperText:
                            'Single simple emoji character (no skin tones or combined emojis)',
                      ),
                      maxLength: 2,
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Location card
          if (latestReport != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Last Known Location',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _InfoRow(
                      icon: Icons.location_on,
                      label: 'Coordinates',
                      value:
                          '${latestReport.latitude.toStringAsFixed(6)}, '
                          '${latestReport.longitude.toStringAsFixed(6)}',
                    ),
                    _InfoRow(
                      icon: Icons.schedule,
                      label: 'Last Seen',
                      value: _formatDateTime(latestReport.dateTime),
                    ),
                    _InfoRow(
                      icon: Icons.gps_fixed,
                      label: 'Accuracy',
                      value: '±${latestReport.horizontalAccuracy}m',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('View on Map'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const MapScreen()),
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.history),
                          label: const Text('History'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  HistoryScreen(beacon: beacon),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Technical details card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Technical Details',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.fingerprint,
                    label: 'Beacon ID',
                    value: beacon.beaconId,
                    copyable: true,
                  ),
                  if (beacon.model != null && beacon.model!.isNotEmpty)
                    _InfoRow(
                      icon: Icons.phone_android,
                      label: 'Model',
                      value: beacon.model!,
                    ),
                  if (beacon.systemVersion != null)
                    _InfoRow(
                      icon: Icons.system_update_alt,
                      label: 'Firmware / OS',
                      value: beacon.systemVersion!,
                    ),
                  if (beacon.pairingDate != null)
                    _InfoRow(
                      icon: Icons.link,
                      label: 'Pairing Date',
                      value: beacon.pairingDate!,
                    ),
                  _InfoRow(
                    icon: Icons.battery_std,
                    label: 'Battery',
                    value: beacon.batteryLevel == 0 ? 'Full' : 'Low',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove Device'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: _confirmRemove,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) =>
      '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
      '${_pad(dt.hour)}:${_pad(dt.minute)}';

  String _pad(int n) => n.toString().padLeft(2, '0');
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool copyable;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.copyable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        )),
                Text(value),
              ],
            ),
          ),
          if (copyable)
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: 'Copy',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Copied to clipboard'),
                      duration: Duration(seconds: 1)),
                );
              },
            ),
        ],
      ),
    );
  }
}
