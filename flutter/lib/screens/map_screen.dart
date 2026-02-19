import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/beacon_information.dart';
import '../models/beacon_location_report.dart';
import '../state/app_state.dart';
import 'history_screen.dart';

/// Displays all beacons with known locations on an interactive map.
///
/// Uses [flutter_map] with OpenStreetMap tiles (no API key required).
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  BeaconInformation? _selectedBeacon;

  // --- Marker cache ----------------------------------------------------------
  // Markers depend on the beacon list, their latest reports, and the current
  // selection. Re-building them on every frame is wasteful. We cache them and
  // rebuild only when the inputs actually change.

  List<Marker> _cachedMarkers = [];
  int _markersBuiltForReportVersion = -1;
  String? _markersBuiltForSelectedBeaconId;
  int _markersBuiltForBeaconCount = -1;

  List<Marker> _getMarkers(
      AppState appState, List<BeaconInformation> beacons) {
    final currentVersion = appState.reportVersion;
    final currentSelectedId = _selectedBeacon?.beaconId;
    final currentCount = beacons.length;

    if (_markersBuiltForReportVersion == currentVersion &&
        _markersBuiltForSelectedBeaconId == currentSelectedId &&
        _markersBuiltForBeaconCount == currentCount) {
      return _cachedMarkers;
    }

    _cachedMarkers = beacons.map((b) {
      final report = appState.latestReportFor(b.beaconId);
      if (report == null) return null;
      return Marker(
        point: LatLng(report.latitude, report.longitude),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => _selectBeacon(b),
          child: _MarkerIcon(
            beacon: b,
            selected: _selectedBeacon?.beaconId == b.beaconId,
          ),
        ),
      );
    }).whereType<Marker>().toList();

    _markersBuiltForReportVersion = currentVersion;
    _markersBuiltForSelectedBeaconId = currentSelectedId;
    _markersBuiltForBeaconCount = currentCount;

    return _cachedMarkers;
  }
  // ---------------------------------------------------------------------------

  void _selectBeacon(BeaconInformation beacon) {
    setState(() => _selectedBeacon = beacon);

    final appState = context.read<AppState>();
    final report = appState.latestReportFor(beacon.beaconId);
    if (report != null) {
      _mapController.move(
        LatLng(report.latitude, report.longitude),
        15,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final beacons = appState.beacons
        .where((b) => appState.latestReportFor(b.beaconId) != null)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => appState.refreshReports(),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildMap(appState, beacons),
          if (_selectedBeacon != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _TagCard(
                beacon: _selectedBeacon!,
                report: appState.latestReportFor(_selectedBeacon!.beaconId)!,
                onClose: () => setState(() => _selectedBeacon = null),
                onHistory: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        HistoryScreen(beacon: _selectedBeacon!),
                  ),
                ),
              ),
            ),
          if (appState.isLoadingReports)
            const Positioned(
              top: 8,
              right: 8,
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: beacons.isEmpty
          ? null
          : SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8),
                itemCount: beacons.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final b = beacons[i];
                  final selected = _selectedBeacon?.beaconId == b.beaconId;
                  return GestureDetector(
                    onTap: () => _selectBeacon(b),
                    child: Chip(
                      avatar: b.isEmojiFilled
                          ? Text(b.emoji!)
                          : const Icon(Icons.location_on, size: 16),
                      label: Text(b.name ?? b.beaconId),
                      backgroundColor: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildMap(
      AppState appState, List<BeaconInformation> beacons) {
    final markers = _getMarkers(appState, beacons);

    final center = markers.isNotEmpty
        ? markers.first.point
        : const LatLng(0, 0);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: markers.isNotEmpty ? 13 : 2,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'dev.wander.opentagviewer',
        ),
        MarkerLayer(markers: markers),
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('© OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}

class _MarkerIcon extends StatelessWidget {
  final BeaconInformation beacon;
  final bool selected;

  const _MarkerIcon({required this.beacon, required this.selected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.primaryContainer,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
      ),
      alignment: Alignment.center,
      child: beacon.isEmojiFilled
          ? Text(beacon.emoji!, style: const TextStyle(fontSize: 16))
          : Icon(
              Icons.location_on,
              size: 20,
              color: selected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onPrimaryContainer,
            ),
    );
  }
}

class _TagCard extends StatelessWidget {
  final BeaconInformation beacon;
  final BeaconLocationReport report;
  final VoidCallback onClose;
  final VoidCallback onHistory;

  const _TagCard({
    required this.beacon,
    required this.report,
    required this.onClose,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (beacon.isEmojiFilled)
                  Text(beacon.emoji!,
                      style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    beacon.name ?? beacon.beaconId,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${report.latitude.toStringAsFixed(6)}, '
              '${report.longitude.toStringAsFixed(6)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Last seen: ${_formatDate(report.dateTime)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.history),
                label: const Text('View History'),
                onPressed: onHistory,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
