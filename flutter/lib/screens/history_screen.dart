import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/beacon_information.dart';
import '../models/beacon_location_report.dart';
import '../state/app_state.dart';

/// Shows the location history for a single beacon on a map with a date picker.
///
/// Mirrors [HistoryViewActivity] from the Android app.
class HistoryScreen extends StatefulWidget {
  final BeaconInformation beacon;

  const HistoryScreen({super.key, required this.beacon});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final MapController _mapController = MapController();

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 1));
  DateTime _endDate = DateTime.now();

  List<BeaconLocationReport> _reports = [];
  bool _loading = false;
  String? _errorMessage;
  BeaconLocationReport? _selectedReport;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _fetchHistory());
  }

  Future<void> _fetchHistory() async {
    final appState = context.read<AppState>();
    final user = appState.currentUser;
    if (user == null) return;

    final plist = widget.beacon.ownedBeaconPlistRaw;
    if (plist == null) {
      setState(() => _errorMessage = 'No plist data for this beacon');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final result = await appState.reportService.getReportsBetween(
        accountToken: user.accountToken,
        beaconIdToPList: {widget.beacon.beaconId: plist},
        anisetteServerUrl: appState.anisetteServerUrl,
        startTimeMs: _startDate.millisecondsSinceEpoch,
        endTimeMs: _endDate.millisecondsSinceEpoch,
      );

      final reports =
          (result[widget.beacon.beaconId] ?? [])
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      setState(() => _reports = reports);

      if (reports.isNotEmpty) {
        _mapController.move(
          LatLng(reports.last.latitude, reports.last.longitude),
          13,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (range == null) return;
    setState(() {
      _startDate = range.start;
      _endDate = range.end;
    });
    await _fetchHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.beacon.name ?? widget.beacon.beaconId),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Change date range',
            onPressed: _pickDateRange,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _fetchHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          // Date range banner
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '${_formatDate(_startDate)} – ${_formatDate(_endDate)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    '${_reports.length} reports',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _errorMessage!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            flex: 3,
            child: _buildMap(),
          ),
          Expanded(
            flex: 2,
            child: _buildReportList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final markers = _reports
        .map((r) => Marker(
              point: LatLng(r.latitude, r.longitude),
              width: 24,
              height: 24,
              child: GestureDetector(
                onTap: () =>
                    setState(() => _selectedReport = r),
                child: Container(
                  decoration: BoxDecoration(
                    color: _selectedReport == r
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ))
        .toList();

    final polylinePoints =
        _reports.map((r) => LatLng(r.latitude, r.longitude)).toList();

    final center = _reports.isNotEmpty
        ? LatLng(_reports.last.latitude, _reports.last.longitude)
        : const LatLng(0, 0);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: _reports.isNotEmpty ? 13 : 2,
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'dev.wander.opentagviewer',
        ),
        if (polylinePoints.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: polylinePoints,
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 3,
              ),
            ],
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

  Widget _buildReportList() {
    if (_reports.isEmpty) {
      return const Center(
          child: Text('No location history for this date range'));
    }

    return ListView.builder(
      reverse: true,
      padding: EdgeInsets.zero,
      itemCount: _reports.length,
      itemBuilder: (context, i) {
        final report = _reports[_reports.length - 1 - i];
        final selected = _selectedReport == report;
        return ListTile(
          selected: selected,
          dense: true,
          leading: Text(
            '${i + 1}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          title: Text(
            '${report.latitude.toStringAsFixed(5)}, '
            '${report.longitude.toStringAsFixed(5)}',
          ),
          subtitle: Text(_formatDateTime(report.dateTime)),
          trailing: selected
              ? const Icon(Icons.location_on, size: 16)
              : null,
          onTap: () {
            setState(() => _selectedReport = report);
            _mapController.move(
              LatLng(report.latitude, report.longitude),
              15,
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';

  String _formatDateTime(DateTime dt) =>
      '${_formatDate(dt)} ${_pad(dt.hour)}:${_pad(dt.minute)}';

  String _pad(int n) => n.toString().padLeft(2, '0');
}
